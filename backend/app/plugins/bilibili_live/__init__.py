from typing import Any, Dict, List, Optional
import asyncio
import time
import aiohttp
import random

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
        emoticon_data = None
        try:
            dm_type = int(getattr(message, 'dm_type', 0) or 0)
        except Exception:
            dm_type = 0

        if dm_type == 1:
            url = ""
            unique = ""
            try:
                url = str(getattr(message, 'emoji_img_url', '') or '')
            except Exception:
                url = ""

            if not url:
                try:
                    raw = getattr(message, 'emoticon_options_dict', None)
                    options = raw() if callable(raw) else raw
                    if isinstance(options, dict):
                        unique = str(options.get('emoticon_unique') or '')
                        url = str(options.get('url') or '')
                except Exception:
                    pass

            if url or unique:
                emoticon_data = {}
                if unique:
                    emoticon_data['emoticon_unique'] = unique
                if url:
                    emoticon_data['url'] = url

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
        self._emoticon_cache: Dict[str, str] = {}
        self._emoticon_cache_ts: float = 0.0
        self._emoticon_cache_ttl: float = 600.0
        self._emoticon_lock = asyncio.Lock()
        self._last_live2d_motion_ts: float = 0.0

    async def _broadcast_live2d_motion_request(self, text: str, force: bool = False) -> None:
        if not self.is_active:
            return
        if not bool(self.config.get("live2d_motion_request_enabled", True)):
            return

        s = str(text or "").strip()
        if not s:
            return

        now = time.time()
        cooldown = float(self.config.get("live2d_motion_request_cooldown", 2.5) or 2.5)
        if not force and (now - float(self._last_live2d_motion_ts or 0.0)) < cooldown:
            return

        chance = float(self.config.get("live2d_motion_request_chance", 0.15) or 0.15)
        if not force:
            is_question = ("?" in s) or ("？" in s)
            has_emoticon = ("[" in s and "]" in s)
            if not is_question and not has_emoticon and random.random() > chance:
                return

        events = self._select_recent_events()[-8:]
        history = []
        for e in events:
            user = str(e.get("user") or "").strip()
            content = str(e.get("content") or "").strip()
            if not content:
                continue
            history.append({"role": "user", "content": f"{user}: {content}" if user else content})

        await live2d_manager.broadcast({
            "type": "motion_request",
            "data": {
                "userText": s,
                "aiText": "",
                "history": history
            }
        })
        self._last_live2d_motion_ts = now

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

                    if not bool(self.config.get("allow_ai_emojis", False)):
                        content += "\n\n要求：回复中不要使用任何 emoji/表情符号。"
                    
                    # Send to ChatService
                    # We use a special user_id to indicate this is a system/agent input
                    await self.chat_service.process_message(
                        content, 
                        user_id="bilibili_agent", 
                        enable_backend_tts=False,
                        tts_mode="sentence"
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

                    if not bool(self.config.get("allow_ai_emojis", False)):
                        prompt += "\n\nDo not use any emoji in your reply."
                    
                    await self.chat_service.process_message(
                        prompt, 
                        user_id="bilibili_agent_sc", # Different ID to avoid memory pollution/confusion? Or same?
                        # Using same ID might be better for continuity, but let's use bilibili_agent for now.
                        enable_backend_tts=False,
                        tts_mode="sentence"
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

    def _normalize_emoticon_key(self, key: str) -> str:
        v = str(key or '').strip()
        if v.startswith('#'):
            v = v[1:]
        if v.startswith('[') and v.endswith(']') and len(v) >= 2:
            v = v[1:-1]
        return v.strip()

    def _collect_emoticon_urls(self, obj: Any, out: Dict[str, str]) -> None:
        if isinstance(obj, dict):
            unique = obj.get('emoticon_unique') or obj.get('emoticon_id') or obj.get('id')
            url = obj.get('url') or obj.get('img_url') or obj.get('image')
            if isinstance(unique, str) and isinstance(url, str):
                u = self._normalize_emoticon_key(unique)
                s = url.strip()
                if u and s and u not in out:
                    out[u] = s
            for v in obj.values():
                self._collect_emoticon_urls(v, out)
            return
        if isinstance(obj, list):
            for it in obj:
                self._collect_emoticon_urls(it, out)

    def _get_room_id(self) -> Optional[int]:
        try:
            room_id_str = str(self.config.get('room_id') or '').strip()
            return int(room_id_str)
        except Exception:
            return None

    async def _get_emoticon_map(self) -> Dict[str, str]:
        now = time.time()
        if self._emoticon_cache and (now - self._emoticon_cache_ts) < self._emoticon_cache_ttl:
            return self._emoticon_cache

        async with self._emoticon_lock:
            now = time.time()
            if self._emoticon_cache and (now - self._emoticon_cache_ts) < self._emoticon_cache_ttl:
                return self._emoticon_cache

            room_id = self._get_room_id()
            if not room_id or not self._session:
                return self._emoticon_cache

            url = 'https://api.live.bilibili.com/xlive/web-ucenter/v2/emoticon/GetEmoticons'
            params = {
                'platform': 'pc',
                'room_id': str(room_id),
            }

            collected: Dict[str, str] = {}
            try:
                async with self._session.get(url, params=params, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                    data = await resp.json(content_type=None)
                    self._collect_emoticon_urls(data, collected)
            except Exception:
                collected = {}

            if collected:
                self._emoticon_cache = collected
                self._emoticon_cache_ts = time.time()

            return self._emoticon_cache

    async def _resolve_emoticon_url(self, unique: str) -> Optional[str]:
        key = self._normalize_emoticon_key(unique)
        if not key:
            return None
        mapping = await self._get_emoticon_map()
        return mapping.get(key)

    async def process_danmaku(self, message: str, user_name: str, emoticon_options: Optional[Dict] = None) -> None:
        extra = {}
        display_message = message

        emoticon: Dict[str, str] = {}
        url = None
        unique = None
        if emoticon_options and isinstance(emoticon_options, dict):
            url = emoticon_options.get('url')
            unique = emoticon_options.get('emoticon_unique')

        if isinstance(unique, str):
            unique = unique.strip()
        else:
            unique = None
        if isinstance(url, str):
            url = url.strip()
        else:
            url = None

        if unique and not url:
            url = await self._resolve_emoticon_url(unique)

        if not unique and not url:
            m = re.search(r'#([A-Za-z0-9_]{3,64})', str(message or ''))
            if m:
                unique = self._normalize_emoticon_key(m.group(1))
                if unique:
                    url = await self._resolve_emoticon_url(unique)

        if not unique and not url:
            m = re.search(r'\[([^\]\n]{1,64})\]', str(message or ''))
            if m:
                unique = self._normalize_emoticon_key(m.group(1))
                if unique:
                    url = await self._resolve_emoticon_url(unique)

        if unique:
            emoticon['emoticon_unique'] = unique
        if url:
            emoticon['url'] = url

        if emoticon:
            extra['emoticon'] = emoticon
            if not str(display_message or '').strip():
                display_message = f"[{emoticon.get('emoticon_unique') or '表情'}]"
            else:
                tag = emoticon.get('emoticon_unique')
                if tag and f'[{tag}]' not in display_message:
                    display_message = f"{display_message} [{tag}]"

        # Buffer for summary
        self._danmaku_buffer.append({
            "user": user_name,
            "content": display_message,
            "timestamp": time.time()
        })

        await self._append_event(
            kind="danmaku",
            user=user_name,
            content=display_message,
            price=None,
            extra=extra
        )
        print(f"[{self.name}] Danmaku from {user_name}: {display_message}")
        
        # Broadcast to Live2D (Middle Display)
        await live2d_manager.broadcast({
            "type": "chat_message",
            "text": display_message,
            "sender": "chat_normal",
            "senderName": user_name
        })
        await self._broadcast_live2d_motion_request(f"{user_name}: {display_message}")

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
        await self._broadcast_live2d_motion_request(f"【SC ¥{price}】{user_name}: {message}", force=True)

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
            emoticon = item.get("emoticon")
            if not content.strip() and isinstance(emoticon, dict):
                unique = str(emoticon.get("emoticon_unique") or "").strip()
                if unique:
                    content = f"[{unique}]"
                elif str(emoticon.get("url") or "").strip():
                    content = "[表情]"
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
