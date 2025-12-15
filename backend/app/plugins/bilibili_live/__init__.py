from typing import Any, Dict, List, Optional
import asyncio
import time
import aiohttp

from ..base import BasePlugin
from app.services.llm_service import LLMService
from app.services.chat_service import ChatService
from app.api.routes.live2d_routes import manager as live2d_manager
import re

# 引入本地的 blivedm 库
# 确保 backend/requirements.txt 中包含 aiohttp, brotli, pure-protobuf, yarl
from .blivedm import BLiveClient, BaseHandler
from .blivedm.models import web as web_models

class BilibiliHandler(BaseHandler):
    def __init__(self, plugin: "BilibiliLivePlugin"):
        self.plugin = plugin

    def _on_danmaku(self, client: BLiveClient, message: web_models.DanmakuMessage):
        # 异步调用插件的处理逻辑
        # 尝试提取 emoticon_options
        emoticon_data = None
        try:
            if hasattr(message, 'emoticon_options_dict'):
                 emoticon_data = message.emoticon_options_dict
        except Exception:
            pass
            
        asyncio.create_task(self.plugin.process_danmaku(message.msg, message.uname, emoticon_data))

    def _on_super_chat(self, client: BLiveClient, message: web_models.SuperChatMessage):
        asyncio.create_task(self.plugin.process_super_chat(message.message, message.uname, message.price))

    def _on_gift(self, client: BLiveClient, message: web_models.GiftMessage):
        asyncio.create_task(self.plugin.process_gift(message))

    def _on_buy_guard(self, client: BLiveClient, message: web_models.GuardBuyMessage):
        asyncio.create_task(self.plugin.process_guard_buy(message))

class BilibiliLivePlugin(BasePlugin):
    def __init__(self, config: Dict[str, Any] | None = None) -> None:
        super().__init__(config=config)
        self.llm = LLMService()
        self.chat_service = ChatService()
        self._ws_task: Optional[asyncio.Task] = None
        self._client: Optional[BLiveClient] = None
        self._session: Optional[aiohttp.ClientSession] = None
        self._events: List[Dict[str, Any]] = []
        self._danmaku_buffer: List[Dict[str, Any]] = []
        self._sc_buffer: List[Dict[str, Any]] = []
        self._summary_task: Optional[asyncio.Task] = None
        self._sc_task: Optional[asyncio.Task] = None

    @property
    def name(self) -> str:
        return "bilibili_live"

    @property
    def description(self) -> str:
        return "Native integration for Bilibili Live (Danmaku/SC/Gifts) using blivedm."

    async def on_startup(self) -> None:
        await super().on_startup()
        
        # Security: Temporarily disable advanced access configs to prevent misuse
        if self.config:
            removed_keys = []
            for key in ["access_key_id", "access_key_secret", "app_id"]:
                if key in self.config:
                    self.config.pop(key)
                    removed_keys.append(key)
            if removed_keys:
                print(f"[{self.name}] Security: Removed disabled advanced configs: {removed_keys}")

        print(f"[{self.name}] Plugin startup, initializing blivedm client...")
        self._session = aiohttp.ClientSession()
        try:
            await self._ensure_ws_started()
        except Exception as e:
            print(f"[{self.name}] Failed to start blivedm client: {e}")
        
        # Start loops
        self._summary_task = asyncio.create_task(self._loop_process_danmaku())
        self._sc_task = asyncio.create_task(self._loop_process_sc())

    async def on_shutdown(self) -> None:
        await super().on_shutdown()
        await self._stop_ws()
        if self._summary_task:
            self._summary_task.cancel()
        if self._sc_task:
            self._sc_task.cancel()
        if self._session:
            await self._session.close()
            self._session = None

    async def _loop_process_danmaku(self) -> None:
        """Periodically summarize buffered danmaku and send to Main Brain."""
        while True:
            try:
                # Interval configurable, default 20s (normal danmaku)
                interval = float(self.config.get("danmaku_interval", 20))
                await asyncio.sleep(interval)
                
                if not self._danmaku_buffer:
                    continue
                
                # Take all items from buffer (limit to max 50 to avoid overflow)
                max_items = int(self.config.get("danmaku_batch_size", 50))
                items = list(self._danmaku_buffer[:max_items])
                # Keep remaining if any? No, usually we clear to avoid stale data.
                # But if traffic is huge, we might drop. Let's just clear.
                self._danmaku_buffer.clear()
                
                # Summarize
                summary = await self.summarize_danmaku_batch(items)
                if summary:
                    print(f"[{self.name}] Sending danmaku summary to Main Brain: {summary[:50]}...")
                    # Construct prompt for the AI
                    prompt_template = self.config.get("prompt_danmaku", 
                        "Current Danmaku Summary: {summary}.\n"
                        "This is a live feed from your stream audience. "
                        "You MUST briefly acknowledge interesting comments, answer questions, or react to the atmosphere. "
                        "Directly address the audience content."
                    )
                    content = prompt_template.format(summary=summary)
                    
                    # Send to ChatService
                    # We use a special user_id to indicate this is a system/agent input
                    await self.chat_service.process_message(
                        content, 
                        user_id="bilibili_agent", 
                        enable_backend_tts=True # Or false if we don't want TTS for summaries
                    )
                    
                    # Broadcast summary to frontend for display
                    await live2d_manager.broadcast({
                        "type": "chat_summary",
                        "content": summary,
                        "timestamp": int(time.time() * 1000)
                    })
            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"[{self.name}] Error in danmaku loop: {e}")
                await asyncio.sleep(5) # Backoff

    async def _loop_process_sc(self) -> None:
        """Periodically check for Super Chats and send them with a delay."""
        # Note: SCs are stored in _sc_buffer with a timestamp.
        # We check every second if any SC has matured (passed the delay time).
        while True:
            try:
                await asyncio.sleep(1)
                
                if not self._sc_buffer:
                    continue
                
                now = time.time()
                delay = float(self.config.get("sc_response_delay", 30)) # Default 30s delay
                
                # Filter items that are ready
                ready_items = []
                remaining_items = []
                
                for item in self._sc_buffer:
                    if now - item["timestamp"] >= delay:
                        ready_items.append(item)
                    else:
                        remaining_items.append(item)
                
                self._sc_buffer = remaining_items
                
                if ready_items:
                    # Process ready SCs immediately (or batch them if multiple ready at once)
                    print(f"[{self.name}] Processing {len(ready_items)} matured SCs...")
                    
                    # For SC, we might want to send them one by one or grouped.
                    # Grouping is safer for the LLM context.
                    summary_text = ""
                    for sc in ready_items:
                         summary_text += f"[SuperChat] {sc['user']} (¥{sc['price']}): {sc['content']}\n"
                    
                    prompt = (
                        f"You received Super Chat(s)!\n{summary_text}\n"
                        "Please respond to these supporters enthusiastically and specifically. "
                        "Thank them for the support."
                    )
                    
                    await self.chat_service.process_message(
                        prompt, 
                        user_id="bilibili_agent_sc", # Different ID to avoid memory pollution/confusion? Or same?
                        # Using same ID might be better for continuity, but let's use bilibili_agent for now.
                        enable_backend_tts=True
                    )

            except asyncio.CancelledError:
                break
            except Exception as e:
                print(f"[{self.name}] Error in SC loop: {e}")
                await asyncio.sleep(5)

    async def on_config_updated(self) -> None:
        await self._stop_ws()
        await self._ensure_ws_started()

    async def handle_event(self, event_type: str, data: Any) -> Optional[Any]:
        return None

    async def process_danmaku(self, message: str, user_name: str, emoticon_options: Optional[Dict] = None) -> None:
        extra = {}
        if emoticon_options:
            extra["emoticon"] = emoticon_options

        # Buffer for summary
        self._danmaku_buffer.append({
            "user": user_name,
            "content": message,
            "timestamp": time.time()
        })

        await self._append_event(
            kind="danmaku",
            user=user_name,
            content=message,
            price=None,
            extra=extra
        )
        print(f"[{self.name}] Danmaku from {user_name}: {message}")
        
        # Broadcast to Live2D (Middle Display)
        await live2d_manager.broadcast({
            "type": "chat_message",
            "text": message,
            "sender": "chat_normal",
            "senderName": user_name
        })

    async def process_super_chat(self, message: str, user_name: str, price: float) -> None:
        # Ad Filtering
        # Block keywords
        ad_keywords = ["加群", "微信", "vx", "QQ", "卖", "代充", "下单", "拼多多", "淘宝", "京东", "领券"]
        if any(k in message for k in ad_keywords):
            print(f"[{self.name}] Blocked potential Ad SC from {user_name}: {message}")
            return

        await self._append_event(
            kind="super_chat",
            user=user_name,
            content=message,
            price=price
        )
        print(f"[{self.name}] SuperChat from {user_name} (¥{price}): {message}")
        
        # Add to SC Buffer for delayed processing
        self._sc_buffer.append({
            "user": user_name,
            "content": message,
            "price": price,
            "timestamp": time.time()
        })
        
        # Broadcast to Live2D
        await live2d_manager.broadcast({
            "type": "chat_message",
            "text": f"【SC ¥{price}】{message}",
            "sender": "chat_sc",
            "senderName": user_name
        })

    async def process_gift(self, message: web_models.GiftMessage) -> None:
        # 过滤掉低价值礼物以减少噪音（可选，这里先不过滤）
        # total_coin 是总瓜子数，1000 金瓜子 = 1 RMB
        # coin_type: 'silver' | 'gold'
        
        price_rmb = 0.0
        if message.coin_type == 'gold':
            price_rmb = message.total_coin / 1000.0
        
        # 构建内容字符串
        content = f"{message.action} {message.gift_name} x{message.num}"
        
        await self._append_event(
            kind="gift",
            user=message.uname,
            content=content,
            price=price_rmb if price_rmb > 0 else None,
            extra={
                "gift_name": message.gift_name,
                "num": message.num,
                "action": message.action,
                "coin_type": message.coin_type,
                "total_coin": message.total_coin
            }
        )
        print(f"[{self.name}] Gift from {message.uname}: {content} (¥{price_rmb})")

    async def process_guard_buy(self, message: web_models.GuardBuyMessage) -> None:
        # guard_level: 1 总督, 2 提督, 3 舰长
        guard_names = {1: "总督", 2: "提督", 3: "舰长"}
        level_name = guard_names.get(message.guard_level, "舰长")
        
        price_rmb = message.price / 1000.0
        
        content = f"购买了 {level_name} x{message.num}"
        
        await self._append_event(
            kind="guard_buy",
            user=message.username,
            content=content,
            price=price_rmb,
            extra={
                "guard_level": message.guard_level,
                "level_name": level_name,
                "num": message.num,
                "gift_name": message.gift_name
            }
        )
        print(f"[{self.name}] Guard Buy from {message.username}: {content} (¥{price_rmb})")

    async def summarize_danmaku_batch(self, items: Optional[List[Dict[str, Any]]] = None) -> str:
        if items is None:
            items = self._select_recent_events()
        if not items:
            return ""

        max_items = int(self.config.get("batch_size", 20) or 20)
        items = items[-max_items:]

        lines: List[str] = []
        for item in items:
            user = str(item.get("user", ""))
            content = str(item.get("content", ""))
            price = item.get("price")
            if price is not None:
                lines.append(f"{user} (¥{price}): {content}")
            else:
                lines.append(f"{user}: {content}")

        joined = "\n".join(lines)

        prompt = (
            "你是一名直播间弹幕整理助手。下面是一段时间内观众的弹幕与醒目留言，请你用中文做一个简洁总结："
            "1. 弹幕趋势：(e.g., 刷屏'666'，讨论游戏，询问主播)"
            "2. 关键话题：(大家在聊什么)"
            "3. 观众情绪：(开心、愤怒、期待、无聊)"
            "请以 '趋势：... | 话题：... | 情绪：...' 的格式输出，保持在一行或简短的三行以内。"
        )

        messages = [
            {"role": "system", "content": prompt},
            {"role": "user", "content": joined},
        ]

        api_key = self.config.get("agent_api_key")
        base_url = self.config.get("agent_base_url")
        model = self.config.get("agent_model")

        summary = await self.llm.get_response(
            messages,
            api_key=api_key,
            base_url=base_url,
            model=model,
            temperature=0.3,
        )
        return summary

    def get_events_since(self, since_ts: Optional[float] = None) -> List[Dict[str, Any]]:
        events = self._select_recent_events()
        if since_ts is None:
            return events
        return [
            e
            for e in events
            if float(e.get("timestamp") or 0) > float(since_ts)
        ]

    def _select_recent_events(self) -> List[Dict[str, Any]]:
        if not self._events:
            return []
        now = time.time()
        window_seconds = int(self.config.get("interval_seconds", 60) or 60)
        cutoff = now - window_seconds
        return [
            e
            for e in self._events
            if float(e.get("timestamp") or 0) >= cutoff
        ]

    async def _append_event(
        self,
        kind: str,
        user: str,
        content: str,
        price: Optional[float],
        extra: Optional[Dict[str, Any]] = None,
    ) -> None:
        highlighted = False
        if kind == "super_chat" and price is not None:
            try:
                value = float(price)
            except Exception:
                value = 0.0
            highlighted = value >= 100.0
        elif kind == "guard_buy":
            highlighted = True
        elif kind == "gift":
             # 只有金瓜子礼物且金额大于一定值才高亮？暂不高亮
             pass

        event = {
            "kind": kind,
            "user": user,
            "content": content,
            "price": price,
            "timestamp": time.time(),
            "highlighted": highlighted,
        }
        if extra:
            event.update(extra)
            
        self._events.append(event)
        max_events = int(self.config.get("max_events", 500) or 500)
        if len(self._events) > max_events:
            self._events = self._events[-max_events:]

    async def _ensure_ws_started(self) -> None:
        if self._ws_task and not self._ws_task.done():
            return
        
        # 这里的 room_id 就是直播间号，不再是身份码
        try:
            room_id_str = str(self.config.get("room_id") or "").strip()
            room_id = int(room_id_str)
        except (ValueError, TypeError):
            print(f"[{self.name}] Invalid or missing room_id")
            return

        if not room_id:
            print(f"[{self.name}] Room ID not configured")
            return

        loop = asyncio.get_running_loop()
        self._ws_task = loop.create_task(self._run_blivedm_client(room_id))

    async def _stop_ws(self) -> None:
        if self._client:
            self._client.stop()
            # client.join() is needed but we can't await it easily here if it blocks
            # But blivedm client stop() just sets a flag, join() waits for the loop.
            # We will rely on _run_blivedm_client to finish when stop() is called.
            pass
            
        if self._ws_task:
            try:
                # 给一点时间让 task 自己结束
                await asyncio.wait_for(self._ws_task, timeout=5)
            except asyncio.TimeoutError:
                print(f"[{self.name}] WebSocket task did not stop in time, cancelling")
                self._ws_task.cancel()
            except Exception as e:
                print(f"[{self.name}] Error stopping WebSocket task: {e}")
        self._ws_task = None
        self._client = None

    async def _run_blivedm_client(self, room_id: int) -> None:
        print(f"[{self.name}] Connecting to room {room_id} using blivedm...")
        
        # 获取 Cookie 配置
        sess_data = self.config.get("sess_data", "")
        bili_jct = self.config.get("bili_jct", "")
        buvid3 = self.config.get("buvid3", "")
        
        # 只有当 sess_data 存在时才设置 Cookie
        if sess_data and self._session:
            # aiohttp 的 CookieJar
            from yarl import URL
            # B站 API 域名
            domains = [
                URL("https://api.bilibili.com"),
                URL("https://api.live.bilibili.com"),
                URL("https://www.bilibili.com")
            ]
            for domain in domains:
                self._session.cookie_jar.update_cookies({
                    "SESSDATA": sess_data,
                    "bili_jct": bili_jct,
                    "buvid3": buvid3,
                }, domain)
            print(f"[{self.name}] Cookies configured for login.")

        self._client = BLiveClient(room_id, session=self._session)
        handler = BilibiliHandler(self)
        self._client.set_handler(handler)
        
        self._client.start()
        try:
            await self._client.join()
        except asyncio.CancelledError:
            print(f"[{self.name}] Client task cancelled")
        except Exception as e:
            print(f"[{self.name}] Client error: {e}")
        finally:
            await self._client.stop_and_close()
            print(f"[{self.name}] Client stopped")
