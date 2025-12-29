import os
import json
import logging
from typing import Dict, Any
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
            on_state=self._set_headful_state
        )
        self._headful_inventory = HeadfulInventoryController(
            logger=logger,
            log_append=self._append_log,
            adapter=self._headful,
            config_provider=lambda: self.config,
        )

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
        self.logs.append(line)
        if len(self.logs) > 500:
            self.logs.pop(0)

    def _set_ms_auth_code(self, code: str | None) -> None:
        self.ms_auth_code = code

    def _set_ms_auth_url(self, url: str | None) -> None:
        self.ms_auth_url = url

    def _set_headful_ready(self, ready: bool) -> None:
        self.headful_ready = ready

    def _set_headful_state(self, state: Dict[str, Any] | None) -> None:
        self._headful_last_state = state

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
                    "vision_stream": False
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
                            "vision_stream": False
                        }
                    }
                    self.config = {**default_config, **loaded_config}
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
        return await self._headful_inventory.run(skill, params or {})

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
        }

def get_plugin():
    return MinecraftMindcraftPlugin()
