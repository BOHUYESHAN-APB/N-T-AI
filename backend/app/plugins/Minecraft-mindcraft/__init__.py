import os
import json
import logging
import asyncio
import httpx
import time
from typing import Any, Dict, Optional
from ..base import BasePlugin
from app.services.live2d_service import manager as live2d_manager
from app.services.audio_service import AudioService
from app.core.config import settings as app_settings
from .headful_adapter import HeadfulAdapter
from .headless_adapter import HeadlessAdapter
from .headful_inventory import HeadfulInventoryController

logger = logging.getLogger(__name__)

class MinecraftMindcraftPlugin(BasePlugin):
    def __init__(self):
        super().__init__()
        self.logs = []
        self.ms_auth_code = None
        self.ms_auth_url = None
        self.is_active = False
        self.audio_service = AudioService()
        self.auto_start = False # Minecraft 插件默认不自动启动，防止性能浪费
        
        # 路径配置
        self.plugin_dir = os.path.dirname(os.path.abspath(__file__))
        self.src_dir = os.path.join(self.plugin_dir, "src")
        self.config_path = os.path.join(self.src_dir, "settings.json")
        # 控制模式：headless（原无头 Node 进程）/ headful（Fabric 模组通讯，占位）
        self.control_mode = "headless"
        self.headful_ready = False
        self._headful_last_state = None
        self._headless = HeadlessAdapter(
            logger=logger,
            src_dir=self.src_dir,
            log_append=self._append_log,
            on_ms_auth_code=self._set_ms_auth_code,
            on_ms_auth_url=self._set_ms_auth_url,
            on_bot_output=self._forward_to_ui
        )
        self._headful = HeadfulAdapter(
            logger=logger,
            log_append=self._append_log,
            on_ready=self._set_headful_ready,
            on_state=self._set_headful_state,
            on_event=self._handle_headful_event,
        )
        self._headful_inventory = HeadfulInventoryController(
            logger=logger,
            log_append=self._append_log,
            adapter=self._headful,
            config_provider=lambda: self.config,
            alert_callback=self._notify_main_brain,
        )
        self._headful_task_queue: asyncio.Queue = asyncio.Queue()
        self._headful_task_worker: Optional[asyncio.Task] = None
        self._headful_task_active = False
        self._headful_task_current: Optional[Dict[str, Any]] = None
        self._headful_paused_tasks: list[Dict[str, Any]] = []
        self._headful_autonomy_task: Optional[asyncio.Task] = None
        self._headful_manual_override_until = 0.0
        self._headful_manual_override_reason: Optional[str] = None
        self._headful_last_command: Optional[Dict[str, Any]] = None
        self._headful_state_label: Optional[str] = None

    @property
    def id(self) -> str:
        return "Minecraft-mindcraft"

    @property
    def name(self) -> str:
        return "Minecraft MindCraft"

    @property
    def description(self) -> str:
        return "基于 MindCraft 的高级 Minecraft 智能代理插件（版本随 MindCraft 原始项目更新，适配 1.21.6）"

    def _append_log(self, line: str) -> None:
        if not line:
            return
        for part in str(line).splitlines():
            if not part:
                continue
            self.logs.append(part)
        if len(self.logs) > 500:
            self.logs.pop(0)

    def _ensure_headful_task_worker(self) -> None:
        if self._headful_task_worker is None or self._headful_task_worker.done():
            self._headful_task_worker = asyncio.create_task(self._run_headful_task_queue())

    async def _run_headful_task_queue(self) -> None:
        while True:
            if (
                self._headful_task_queue.empty()
                and self._headful_paused_tasks
                and not self._headful_manual_override_active()
            ):
                paused = self._headful_paused_tasks.pop(0)
                await self._headful_task_queue.put(paused)
                self._append_log(f"[headful-queue] resume paused: {paused.get('goal')}")
            task = await self._headful_task_queue.get()
            if not isinstance(task, dict):
                self._headful_task_queue.task_done()
                continue
            await self._wait_for_manual_override_clear()
            goal = task.get("goal") or ""
            params = task.get("params") or {}
            source = task.get("source") or "main-brain"
            sender = task.get("sender") or ""
            self._headful_task_active = True
            self._headful_task_current = task
            self._refresh_headful_state_label()
            self._append_log(f"[headful-queue] start {source} {sender}: {goal}")
            try:
                result = await self._headful_inventory.run("plan_execute", params)
                if not result.get("ok"):
                    self._append_log(f"[headful-queue] failed: {result.get('error')}")
                else:
                    self._append_log(f"[headful-queue] done: {goal}")
            except Exception as exc:
                self._append_log(f"[headful-queue] exception: {exc}")
            finally:
                self._headful_task_active = False
                self._headful_task_current = None
                self._headful_task_queue.task_done()
                self._refresh_headful_state_label()

    def _ensure_headful_autonomy_worker(self) -> None:
        if self._headful_autonomy_task is None or self._headful_autonomy_task.done():
            self._headful_autonomy_task = asyncio.create_task(
                self._run_headful_autonomy_loop()
            )

    async def _run_headful_autonomy_loop(self) -> None:
        while True:
            cfg = self._headful_chat_config()
            try:
                interval = float(cfg.get("autonomy_tick_interval_sec", 1.0))
            except (TypeError, ValueError):
                interval = 1.0
            if interval < 0.5:
                interval = 0.5
            await asyncio.sleep(interval)
            if self.control_mode != "headful" or not self.is_active:
                continue
            if not self.headful_ready:
                continue
            if not bool(cfg.get("autonomy_enabled", False)):
                continue
            if self._headful_manual_override_active():
                continue
            if self._headful_task_active or self._headful_task_queue.qsize() > 0:
                continue
            try:
                result = await self._headful_inventory.run("autonomy_tick", {})
                if isinstance(result, dict) and result.get("error"):
                    if result.get("error") not in {"screen_open", "autonomy_disabled"}:
                        self._append_log(f"[autonomy] {result.get('error')}")
            except Exception as exc:
                self._append_log(f"[autonomy] exception: {exc}")

    async def _enqueue_headful_task(
        self,
        goal: str,
        params: Dict[str, Any],
        source: str,
        sender: str,
    ) -> Dict[str, Any]:
        cfg = self._headful_chat_config()
        interrupt_current = bool(params.get("interrupt_current", False))
        if not interrupt_current:
            interrupt_current = bool(cfg.get("interrupt_on_new_command", False))
        if (
            interrupt_current
            and self._headful_task_active
            and isinstance(self._headful_task_current, dict)
        ):
            paused = dict(self._headful_task_current)
            paused["paused_at"] = time.time()
            paused["paused_by"] = {"source": source, "sender": sender, "goal": goal}
            self._headful_paused_tasks.append(paused)
            await self._headful_inventory.cancel_current()
            self._append_log(f"[headful-queue] paused current task: {paused.get('goal')}")
        await self._headful_task_queue.put(
            {"goal": goal, "params": params, "source": source, "sender": sender}
        )
        self._ensure_headful_task_worker()
        self._refresh_headful_state_label()
        return {
            "queued": True,
            "queue_length": self._headful_task_queue.qsize(),
        }

    async def cancel_headful_tasks(self) -> Dict[str, Any]:
        cleared = 0
        while True:
            try:
                self._headful_task_queue.get_nowait()
                self._headful_task_queue.task_done()
                cleared += 1
            except asyncio.QueueEmpty:
                break
        self._headful_paused_tasks.clear()
        self._headful_task_current = None
        cancel_result = await self._headful_inventory.cancel_current()
        self._append_log(f"[headful-queue] cancel requested, cleared={cleared}")
        self._refresh_headful_state_label()
        return {"ok": True, "cleared": cleared, "cancelled": cancel_result.get("ok")}

    def _set_ms_auth_code(self, code: str | None) -> None:
        self.ms_auth_code = code

    def _set_ms_auth_url(self, url: str | None) -> None:
        self.ms_auth_url = url

    def _set_headful_ready(self, ready: bool) -> None:
        self.headful_ready = ready

    def _set_headful_state(self, state: Dict[str, Any] | None) -> None:
        self._headful_last_state = state

    def _headful_manual_override_active(self) -> bool:
        return time.time() < self._headful_manual_override_until

    async def _wait_for_manual_override_clear(self) -> None:
        while self._headful_manual_override_active():
            await asyncio.sleep(0.25)

    def _headful_chat_config(self) -> Dict[str, Any]:
        cfg = self.config.get("headful", {})
        return cfg if isinstance(cfg, dict) else {}

    def _compute_headful_state_label(self) -> str:
        if self._headful_manual_override_active():
            return "manual"
        if self._headful_task_active:
            return "running"
        if self._headful_task_queue.qsize() > 0:
            return "queued"
        if self._headful_paused_tasks:
            return "paused"
        return "idle"

    def _refresh_headful_state_label(self) -> None:
        label = self._compute_headful_state_label()
        if label != self._headful_state_label:
            self._headful_state_label = label
            self._append_log(f"[headful-state] {label}")

    def _build_headful_status(self) -> Dict[str, Any]:
        state = self._headful_last_state or {}
        screen = getattr(self._headful, "last_screen", None) or {}
        queue_length = self._headful_task_queue.qsize()
        paused_count = len(self._headful_paused_tasks)
        manual_active = self._headful_manual_override_active()
        task_state = "idle"
        if self._headful_task_active:
            task_state = "running"
        elif queue_length > 0:
            task_state = "queued"
        elif paused_count > 0:
            task_state = "paused"
        current = self._headful_task_current or {}
        position = None
        try:
            position = {
                "x": float(state.get("x")),
                "y": float(state.get("y")),
                "z": float(state.get("z")),
                "dimension": state.get("dimension"),
            }
        except (TypeError, ValueError):
            position = None
        return {
            "control": "manual" if manual_active else "ai",
            "manual_reason": self._headful_manual_override_reason,
            "manual_until": self._headful_manual_override_until if manual_active else None,
            "focused": state.get("focused"),
            "task_state": task_state,
            "current_goal": current.get("goal"),
            "current_source": current.get("source"),
            "current_sender": current.get("sender"),
            "queue_length": queue_length,
            "paused_count": paused_count,
            "screen_open": screen.get("screenOpen"),
            "screen_title": screen.get("title"),
            "position": position,
            "last_command": self._headful_last_command,
        }

    def _chat_sender_allowed(self, sender: str, cfg: Dict[str, Any]) -> bool:
        whitelist = cfg.get("chat_whitelist", [])
        if isinstance(whitelist, str):
            whitelist = [whitelist]
        if not isinstance(whitelist, list):
            return True
        normalized = [str(x).strip().lower() for x in whitelist if str(x).strip()]
        if not normalized:
            return True
        if "*" in normalized:
            return True
        sender_norm = (sender or "").strip().lower()
        return sender_norm in normalized

    def _apply_chat_prefix(self, message: str, cfg: Dict[str, Any]) -> Optional[str]:
        prefixes = cfg.get("chat_command_prefixes", [])
        if isinstance(prefixes, str):
            prefixes = [prefixes]
        if not isinstance(prefixes, list):
            return message
        cleaned = [str(p) for p in prefixes if str(p)]
        if not cleaned:
            return message
        for prefix in cleaned:
            if message.startswith(prefix):
                if cfg.get("chat_strip_prefix", True):
                    return message[len(prefix):].strip()
                return message
        return None

    async def _maybe_plan_from_chat(
        self,
        message: str,
        sender: str,
        source: str,
        is_self: bool = False,
    ) -> bool:
        goal = self._prepare_chat_goal(message, sender, source, is_self=is_self)
        if not goal:
            return False
        params: Dict[str, Any] = {"goal": goal}
        rag_user_id = self.config.get("rag_user_id") or self.config.get("agent_name")
        if rag_user_id:
            params["rag_user_id"] = rag_user_id
        cfg = self._headful_chat_config()
        if "chat_use_rag" in cfg:
            params["use_rag"] = bool(cfg.get("chat_use_rag"))
        if "chat_use_mindcraft_docs" in cfg:
            params["use_mindcraft_docs"] = bool(cfg.get("chat_use_mindcraft_docs"))
        if self._chat_plan_mode(cfg) == "direct":
            params["planner_mode"] = "rules_only"
        self._append_log(f"Headful chat queued ({source}) {sender}: {goal}")
        await self._enqueue_headful_task(goal, params, source=source, sender=sender)
        return True

    def _prepare_chat_goal(
        self,
        message: str,
        sender: str,
        source: str,
        is_self: bool = False,
    ) -> Optional[str]:
        cfg = self._headful_chat_config()
        if not cfg.get("chat_plan_enabled", False):
            return None
        if source == "game" and not cfg.get("chat_plan_game", True):
            return None
        if source == "frontend" and not cfg.get("chat_plan_frontend", True):
            return None
        if is_self and cfg.get("chat_ignore_self", True):
            return None
        if source == "game" and not self._chat_sender_allowed(sender, cfg):
            return None
        message = (message or "").strip()
        if not message:
            return None
        prefixed = self._apply_chat_prefix(message, cfg)
        if prefixed is None or not prefixed.strip():
            return None
        return prefixed.strip()

    def _chat_plan_mode(self, cfg: Dict[str, Any]) -> str:
        raw = cfg.get("chat_plan_mode", "main_brain")
        if isinstance(raw, str):
            mode = raw.strip().lower()
            if mode in {"main_brain", "brain"}:
                return "main_brain"
            if mode in {"direct", "plugin"}:
                return "direct"
        return "main_brain"

    async def _forward_chat_to_main_brain(
        self,
        message: str,
        sender: str,
        source: str,
        is_self: bool = False,
    ) -> bool:
        goal = self._prepare_chat_goal(message, sender, source, is_self=is_self)
        if not goal:
            return False
        cfg = self._headful_chat_config()
        prefix = cfg.get("chat_brain_prefix", "【MC】")
        source_label = "游戏" if source == "game" else "前端" if source == "frontend" else source
        header = f"{prefix}{source_label}"
        if sender:
            header += f"/{sender}: "
        else:
            header += ": "
        payload = header + goal
        self._append_log(f"[main-brain] forward {source_label} {sender}: {goal}")
        user_id = cfg.get("chat_brain_user_id") or "minecraft_chat"
        from app.services.chat_service import ChatService

        chat_service = ChatService()
        await chat_service.process_message(
            message=payload,
            user_id=user_id,
            enable_search=False,
            enable_backend_tts=False,
            tts_mode="sentence",
        )
        return True

    async def _handle_headful_event(self, payload: Dict[str, Any]) -> None:
        event = payload.get("event")
        if event == "manual_control":
            cfg = self._headful_chat_config()
            if not bool(cfg.get("manual_override_enabled", True)):
                return
            active = bool(payload.get("active", False))
            reason = str(payload.get("reason") or "")
            if active:
                timeout = cfg.get("manual_override_timeout_sec", 10.0)
                try:
                    timeout = float(timeout)
                except (TypeError, ValueError):
                    timeout = 10.0
                until_ms = payload.get("until_ms")
                if isinstance(until_ms, (int, float)) and until_ms > 0:
                    until_sec = float(until_ms) / 1000.0
                else:
                    until_sec = time.time() + max(timeout, 1.0)
                if until_sec > self._headful_manual_override_until:
                    self._headful_manual_override_until = until_sec
                self._headful_manual_override_reason = reason or "manual_input"
                await self._headful_inventory.cancel_current()
                self._append_log(
                    f"[manual] active reason={self._headful_manual_override_reason} until={self._headful_manual_override_until:.1f}"
                )
            else:
                self._headful_manual_override_until = 0.0
                self._headful_manual_override_reason = None
                self._append_log("[manual] released")
            self._refresh_headful_state_label()
            return
        if event != "chat":
            return
        if self.control_mode != "headful":
            return
        message = payload.get("message") or payload.get("text") or ""
        sender = payload.get("sender") or payload.get("senderName") or ""
        is_self = bool(payload.get("self", False))
        cfg = self._headful_chat_config()
        if self._chat_plan_mode(cfg) == "main_brain":
            await self._forward_chat_to_main_brain(
                str(message),
                str(sender),
                source="game",
                is_self=is_self,
            )
        else:
            await self._maybe_plan_from_chat(
                str(message),
                str(sender),
                source="game",
                is_self=is_self,
            )

    async def setup(self):
        """初始化插件配置，从本地 settings.json 加载"""
        logger.info(f"[{self.name}] 正在初始化配置，路径: {self.config_path}")
        if not os.path.exists(self.config_path):
            default_config = {
                "minecraft_version": "auto",
                "host": "127.0.0.1",
                "port": -1,
                "auth": "offline",
                "mindserver_port": 8080,
                "profiles": ["./profiles/andy-4.json"],
                "load_memory": False,
                "init_message": "你好！我是你的 AI 助手。",
                "ntai_backend_url": "http://127.0.0.1:23456",
                "language": "zh",
                "auto_start": False,
                "control_mode": "headless",
                "rag_user_id": "",
                "headful": {
                    "host": "127.0.0.1",
                    "port": 8765,
                    "token": "",
                    "event_interval_ms": 200,
                    "scan_radius": 16,
                    "vision_stream": False,
                    "debug": False,
                    "debug_chat": False,
                    "chat_plan_enabled": True,
                    "chat_plan_game": True,
                    "chat_plan_frontend": True,
                    "chat_plan_mode": "main_brain",
                    "chat_plan_fallback_direct": True,
                    "chat_ignore_self": True,
                    "chat_whitelist": [],
                    "chat_command_prefixes": [],
                    "chat_strip_prefix": True,
                    "chat_use_rag": True,
                    "chat_use_mindcraft_docs": True,
                    "chat_brain_prefix": "【MC】",
                    "chat_brain_user_id": "minecraft_chat",
                    "manual_override_enabled": True,
                    "manual_override_timeout_sec": 10.0,
                    "auto_open_crafting_table": True,
                    "auto_gather_base_items": True,
                    "auto_collect_from_containers": True,
                    "auto_gather_radius": 12,
                    "container_interact_distance": 2.0,
                    "workstation_interact_distance": 2.0,
                    "dig_area_max_blocks": 512,
                    "dig_attack_ms": 1200,
                    "dig_distance": 3.2,
                    "dig_move_timeout": 4.0,
                    "dig_look_duration_ms": 160,
                    "dig_step_delay_ms": 80,
                    "dig_progress_every": 20,
                    "autonomy_enabled": True,
                    "autonomy_tick_interval_sec": 1.0,
                    "autonomy_guard": True,
                    "autonomy_gather": True,
                    "autonomy_look_players": True,
                    "autonomy_idle_look": True,
                    "autonomy_patrol": True,
                    "autonomy_harvest_crops": True,
                    "autonomy_harvest_mature_only": True,
                    "autonomy_guard_interval_sec": 2.0,
                    "autonomy_gather_interval_sec": 18.0,
                    "autonomy_harvest_interval_sec": 10.0,
                    "autonomy_patrol_interval_sec": 8.0,
                    "autonomy_patrol_radius": 4.0,
                    "autonomy_patrol_distance": 2.5
                }
            }
            try:
                os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    json.dump(default_config, f, indent=4)
                self.config = default_config
                logger.info(f"[{self.name}] 已创建默认配置文件")
            except Exception as e:
                logger.error(f"[{self.name}] 创建默认配置文件失败: {e}")
                self.config = default_config
        else:
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    loaded_config = json.load(f)
                    # 合并默认值，防止旧配置文件缺少新字段
                    default_config = {
                        "mindserver_port": 8080,
                        "auto_start": False,
                        "language": "zh",
                        "ntai_backend_url": "http://127.0.0.1:23456",
                        "control_mode": "headless",
                        "rag_user_id": "",
                        "headful": {
                            "host": "127.0.0.1",
                            "port": 8765,
                            "token": "",
                            "event_interval_ms": 200,
                            "scan_radius": 16,
                            "vision_stream": False,
                            "debug": False,
                            "debug_chat": False,
                            "chat_plan_enabled": True,
                            "chat_plan_game": True,
                            "chat_plan_frontend": True,
                            "chat_plan_mode": "main_brain",
                            "chat_plan_fallback_direct": True,
                            "chat_ignore_self": True,
                            "chat_whitelist": [],
                            "chat_command_prefixes": [],
                            "chat_strip_prefix": True,
                            "chat_use_rag": True,
                            "chat_use_mindcraft_docs": True,
                            "chat_brain_prefix": "【MC】",
                            "chat_brain_user_id": "minecraft_chat",
                            "manual_override_enabled": True,
                            "manual_override_timeout_sec": 10.0,
                            "auto_open_crafting_table": True,
                            "auto_gather_base_items": True,
                            "auto_collect_from_containers": True,
                            "auto_gather_radius": 12,
                            "container_interact_distance": 2.0,
                            "workstation_interact_distance": 2.0,
                            "dig_area_max_blocks": 512,
                            "dig_attack_ms": 1200,
                            "dig_distance": 3.2,
                            "dig_move_timeout": 4.0,
                            "dig_look_duration_ms": 160,
                            "dig_step_delay_ms": 80,
                            "dig_progress_every": 20,
                            "autonomy_enabled": True,
                            "autonomy_tick_interval_sec": 1.0,
                            "autonomy_guard": True,
                            "autonomy_gather": True,
                            "autonomy_look_players": True,
                            "autonomy_idle_look": True,
                            "autonomy_patrol": True,
                            "autonomy_harvest_crops": True,
                            "autonomy_harvest_mature_only": True,
                            "autonomy_guard_interval_sec": 2.0,
                            "autonomy_gather_interval_sec": 18.0,
                            "autonomy_harvest_interval_sec": 10.0,
                            "autonomy_patrol_interval_sec": 8.0,
                            "autonomy_patrol_radius": 4.0,
                            "autonomy_patrol_distance": 2.5
                        }
                    }
                    loaded_headful = loaded_config.get("headful")
                    if isinstance(loaded_headful, dict):
                        merged_headful = {**default_config["headful"], **loaded_headful}
                    else:
                        merged_headful = default_config["headful"]
                    self.config = {**default_config, **loaded_config, "headful": merged_headful}
                logger.info(f"[{self.name}] 已从本地加载配置")
            except Exception as e:
                logger.error(f"[{self.name}] 加载本地配置失败，将使用内存中的默认值: {e}")
                self.config = {
                    "mindserver_port": 8080,
                    "auto_start": False
                }
        # 同步控制模式占位
        self.control_mode = self.config.get("control_mode", "headless")
        self.headful_ready = False
        return True

    async def on_startup(self) -> None:
        """插件启动时调用（如果 auto_start 为 True）"""
        await super().on_startup()
        logger.info(f"[{self.name}] 正在执行自动启动...")
        await self.activate()

    async def on_shutdown(self) -> None:
        """插件关闭时调用"""
        await super().on_shutdown()
        await self.deactivate()

    async def activate(self):
        """启动插件进程"""
        mode = self.config.get("control_mode", "headless")
        self.control_mode = mode
        if self.is_active:
            logger.info(f"[{self.name}] 插件已经处于激活状态 (mode={mode})")
            return True

        if mode == "headful":
            # headful（Fabric 模组）模式：连接本地 WS
            self._append_log("Headful 模式：正在连接 Fabric 模组 (默认 127.0.0.1)。")
            self.headful_ready = False
            self._headful_last_state = None
            self.is_active = True
            ok = await self._headful.activate(self.config.get("headful", {}))
            if not ok:
                self.is_active = False
            else:
                self._ensure_headful_autonomy_worker()
            logger.info(f"[{self.name}] 以 headful 模式启动，尝试连接模组 WS。")
            return ok
        
        combined_config = self.config.copy()
        host = combined_config.get("host", "127.0.0.1")
        port = combined_config.get("port", 25565)
        logger.info(f"[{self.name}] 正在尝试激活插件... 目标服务器: {host}:{port}")
        self._append_log(f"Activating plugin... Target server: {host}:{port}")

        ok = await self._headless.activate(self.config)
        self.is_active = ok
        return ok

    async def deactivate(self):
        """停止插件进程"""
        mode = self.config.get("control_mode", "headless")
        if mode == "headful":
            if self._headful_autonomy_task is not None:
                self._headful_autonomy_task.cancel()
                try:
                    await self._headful_autonomy_task
                except Exception:
                    pass
                self._headful_autonomy_task = None
            await self._headful.deactivate()
            self.is_active = False
            self.headful_ready = False
            self._append_log("Headful 模式：已断开模组连接。")
            return True

        ok = await self._headless.deactivate()
        self.is_active = False
        logger.info("Minecraft-mindcraft 插件已停止")
        return ok

    async def on_config_updated(self):
        """当配置从外部更新时同步到本地 settings.json 并重启插件（如果已激活）"""
        logger.info(f"[{self.name}] 配置已更新，正在保存到: {self.config_path}")
        try:
            # 同步 auto_start 状态到插件实例
            self.auto_start = self.config.get("auto_start", False)
            
            # 保存到本地文件
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4)
            logger.info(f"[{self.name}] 配置已持久化到本地")
            
            # 如果插件当前是激活状态，则重启以应用新配置
            if self.is_active:
                logger.info(f"[{self.name}] 插件处于激活状态，正在重启以应用新配置...")
                await self.deactivate()
                await self.activate()
        except Exception as e:
            logger.error(f"[{self.name}] 处理配置更新失败: {e}")

    async def _forward_to_ui(self, agent_name: str, message: str):
        """将 Minecraft 消息转发到主界面并触发前端 TTS"""
        enable_tts = False
        
        # 发送原始消息，前端负责统一加前缀
        display_message = message
        
        # 广播到 Live2D/WebSocket 界面
        payload = {
            "type": "chat_message",
            "text": display_message,
            "sender": "minecraft",
            "senderName": agent_name
        }
        
        # 如果前端开启了 TTS，则生成语音并添加到 payload
        if enable_tts:
            try:
                # 强制使用 SiliconFlow API，因为 DeepSeek 不支持 TTS
                tts_api_key = getattr(app_settings, "SILICONFLOW_API_KEY", None)
                tts_base_url = "https://api.siliconflow.cn/v1"
                
                # 如果没有全局 SiliconFlow Key，尝试检查插件配置是否显式指定了 SiliconFlow
                if not tts_api_key:
                    plugin_base_url = self.config.get("agent_base_url", "")
                    if "siliconflow" in plugin_base_url.lower():
                        tts_api_key = self.config.get("agent_api_key")
                        tts_base_url = plugin_base_url
                
                if tts_api_key:
                    logger.info(f"[{self.name}] 正在为消息生成 TTS: {message[:20]}... (API: {tts_base_url})")
                    audio_bytes = await self.audio_service.generate_speech(
                        text=message,
                        api_key=tts_api_key,
                        base_url=tts_base_url,
                        model="FunAudioLLM/CosyVoice2-0.5B", # 默认模型
                        voice="fishaudio/fish-speech-1.4", # 默认音色
                        response_format="wav" # 强制要求 wav 以支持 Live2D
                    )
                    if audio_bytes:
                        import base64
                        b64_audio = base64.b64encode(audio_bytes).decode("utf-8")
                        payload["audioData"] = b64_audio
                        payload["audio_type"] = "wav"
            except Exception as e:
                logger.error(f"Minecraft 前端 TTS 生成失败: {e}", exc_info=True)
        
        await live2d_manager.broadcast(payload)

    async def _notify_main_brain(
        self, message: str, payload: Optional[Dict[str, Any]] = None
    ) -> None:
        if not message:
            return
        agent_name = self.config.get("agent_name") or "minecraft"
        packet = {
            "type": "chat_message",
            "text": message,
            "sender": "minecraft_alert",
            "senderName": agent_name,
            "alert": True,
        }
        if payload:
            packet["meta"] = payload
        self._append_log(f"[main-brain-alert] {message}")
        await live2d_manager.broadcast(packet)

    async def send_headful_message(self, message: str) -> bool:
        """将文本消息发送给 headful 模组（chat/command 兼容）。"""
        return await self._headful.send_message(message, self.config.get("headful", {}))

    async def send_headful_action(self, action: Dict[str, Any]) -> bool:
        """转发 headful 动作 JSON 到模组。"""
        return await self._headful.send_action(action, self.config.get("headful", {}))

    async def run_headful_skill(self, skill: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """执行 headful 背包/容器技能（基于屏幕快照与槽位操作）。"""
        if self.control_mode != "headful":
            return {"ok": False, "error": "not_headful"}
        try:
            skill_name = (skill or "").strip().lower()
            if skill_name in {"cancel", "cancel_current", "abort"}:
                return await self.cancel_headful_tasks()
            result = await self._headful_inventory.run(skill, params or {})
            return self._headful_inventory.serialize_result(result)
        except Exception as exc:
            logger.exception("[Minecraft-mindcraft] Headful skill failed: %s", skill)
            self._append_log(f"Headful skill exception: {exc}")
            return {"ok": False, "error": "exception", "detail": str(exc)}

    async def handle_event(self, event_type: str, data: Any) -> Optional[Any]:
        if event_type != "minecraft_command":
            return None
        payload = data or {}
        goal = payload.get("goal") or payload.get("command") or payload.get("message")
        if not goal:
            return {"status": "error", "error": "missing_goal"}
        sender = payload.get("sender") or "main-brain"
        source = payload.get("source") or "main-brain"
        if self.control_mode == "headful":
            params: Dict[str, Any] = {"goal": str(goal)}
            if payload.get("interrupt_current"):
                params["interrupt_current"] = True
            llm_api_key = payload.get("llm_api_key")
            llm_base_url = payload.get("llm_base_url")
            llm_model = payload.get("llm_model")
            embedding_api_key = payload.get("embedding_api_key")
            embedding_base_url = payload.get("embedding_base_url")
            embedding_model = payload.get("embedding_model")
            if llm_api_key:
                params["llm_api_key"] = llm_api_key
            if llm_base_url:
                params["llm_base_url"] = llm_base_url
            if llm_model:
                params["llm_model"] = llm_model
            if embedding_api_key:
                params["embedding_api_key"] = embedding_api_key
            if embedding_base_url:
                params["embedding_base_url"] = embedding_base_url
            if embedding_model:
                params["embedding_model"] = embedding_model
            rag_user_id = self.config.get("rag_user_id") or self.config.get("agent_name")
            if rag_user_id:
                params["rag_user_id"] = rag_user_id
            cfg = self._headful_chat_config()
            if "chat_use_rag" in cfg:
                params["use_rag"] = bool(cfg.get("chat_use_rag"))
            if "chat_use_mindcraft_docs" in cfg:
                params["use_mindcraft_docs"] = bool(cfg.get("chat_use_mindcraft_docs"))
            llm_configured = bool(llm_api_key or llm_base_url or llm_model)
            embedding_configured = bool(embedding_api_key or embedding_base_url or embedding_model)
            self._headful_last_command = {
                "goal": str(goal),
                "source": source,
                "sender": sender,
                "llm_model": llm_model,
                "embedding_model": embedding_model,
                "use_rag": params.get("use_rag"),
                "use_mindcraft_docs": params.get("use_mindcraft_docs"),
                "interrupt_current": bool(payload.get("interrupt_current")),
                "llm_configured": llm_configured,
                "embedding_configured": embedding_configured,
                "timestamp": time.time(),
            }
            self._append_log(f"[{source}] command: {goal}")
            self._append_log(
                "[agent-payload] "
                f"llm_model={llm_model or '-'} embedding_model={embedding_model or '-'} "
                f"use_rag={params.get('use_rag')} use_docs={params.get('use_mindcraft_docs')} "
                f"interrupt={bool(payload.get('interrupt_current'))} "
                f"llm_cfg={llm_configured} emb_cfg={embedding_configured}"
            )
            queued = await self._enqueue_headful_task(
                str(goal),
                params,
                source=source,
                sender=sender,
            )
            return {"status": "received", "queued": queued}

        ms_port = self.config.get("mindserver_port", 8080)
        url = f"http://localhost:{ms_port}/api/send-message"
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(
                    url,
                    json={"agent": self.config.get("agent_name"), "from": sender, "message": str(goal)},
                    timeout=5.0,
                )
                if resp.status_code == 200:
                    return {"status": "received"}
                return {"status": "error", "detail": resp.text}
        except Exception as exc:
            return {"status": "error", "detail": str(exc)}

    async def handle_frontend_chat(self, message: str, sender: str = "frontend") -> bool:
        if self.control_mode != "headful":
            return False
        cfg = self._headful_chat_config()
        if self._chat_plan_mode(cfg) == "main_brain":
            try:
                return await self._forward_chat_to_main_brain(
                    message,
                    sender,
                    source="frontend",
                    is_self=False,
                )
            except Exception as exc:
                self._append_log(f"[main-brain] forward failed: {exc}")
                if cfg.get("chat_plan_fallback_direct", True):
                    return await self._maybe_plan_from_chat(
                        message,
                        sender,
                        source="frontend",
                        is_self=False,
                    )
                return False
        return await self._maybe_plan_from_chat(
            message,
            sender,
            source="frontend",
            is_self=False,
        )

    async def get_status(self) -> Dict[str, Any]:
        """获取插件状态，供前端轮询"""
        return {
            "id": self.id,
            "is_active": self.is_active,
            "ms_auth_code": self.ms_auth_code,
            "ms_auth_url": self.ms_auth_url,
            "logs": self.logs[-50:] if self.logs else [],
            "control_mode": self.control_mode,
            "headful_ready": self.headful_ready,
            "headful_state": self._headful_last_state,
            "headful_screen": getattr(self._headful, "last_screen", None),
            "headful_plan": getattr(self._headful_inventory, "last_plan", None),
            "headful_queue_length": self._headful_task_queue.qsize(),
            "headful_task_active": self._headful_task_active,
            "headful_status": self._build_headful_status(),
        }

def get_plugin():
    return MinecraftMindcraftPlugin()
