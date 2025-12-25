import os
import subprocess
import threading
import re
import json
import logging
import asyncio
from typing import Dict, Any, List, Optional
from ..base import BasePlugin
from app.services.live2d_service import manager as live2d_manager
from app.services.audio_service import AudioService
from app.services.system_state import system_state
from app.core.config import settings as app_settings

logger = logging.getLogger(__name__)

class MinecraftMindcraftPlugin(BasePlugin):
    def __init__(self):
        super().__init__()
        self._process = None
        self._thread = None
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

    @property
    def id(self) -> str:
        return "Minecraft-mindcraft"

    @property
    def name(self) -> str:
        return "Minecraft MindCraft"

    @property
    def description(self) -> str:
        return "基于 MindCraft 的高级 Minecraft 智能代理插件"

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
                "auto_start": False
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
                        "ntai_backend_url": "http://127.0.0.1:23456"
                    }
                    self.config = {**default_config, **loaded_config}
                logger.info(f"[{self.name}] 已从本地加载配置")
            except Exception as e:
                logger.error(f"[{self.name}] 加载本地配置失败，将使用内存中的默认值: {e}")
                self.config = {
                    "mindserver_port": 8080,
                    "auto_start": False
                }
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
        if self.is_active:
            logger.info(f"[{self.name}] 插件已经处于激活状态")
            return True
        
        logger.info(f"[{self.name}] 正在尝试激活插件...")
        
        # 获取当前事件循环，供后台线程使用
        try:
            self.loop = asyncio.get_running_loop()
        except RuntimeError:
            self.loop = asyncio.get_event_loop()
        
        # 清除旧的验证码
        self.ms_auth_code = None
        self.ms_auth_url = None
        
        try:
            # 确保 src 目录存在
            if not os.path.exists(self.src_dir):
                logger.error(f"[{self.name}] 源码目录不存在: {self.src_dir}")
                self.logs.append(f"ERROR: Source directory not found: {self.src_dir}")
                return False

            # 检查 main.js 是否存在
            main_js_path = os.path.join(self.src_dir, "main.js")
            if not os.path.exists(main_js_path):
                logger.error(f"[{self.name}] 找不到入口文件: {main_js_path}")
                self.logs.append(f"ERROR: Entry file not found: {main_js_path}")
                return False

            # 检查 node_modules，如果不存在则尝试安装 (可选，但建议提醒)
            node_modules_path = os.path.join(self.src_dir, "node_modules")
            if not os.path.exists(node_modules_path):
                logger.warning(f"[{self.name}] 找不到 node_modules，可能需要运行 npm install")
                self.logs.append("WARNING: node_modules not found. Please run 'npm install' in the plugin/src directory.")

            # 获取配置
            combined_config = self.config.copy()
            
            # 处理 AI 名称映射
            if combined_config.get("agent_name"):
                if combined_config.get("auth") == "offline":
                    combined_config["username"] = combined_config["agent_name"]
            
            # 处理微软登录配置映射
            if combined_config.get("auth") == "microsoft":
                if combined_config.get("ms_email"):
                    combined_config["username"] = combined_config["ms_email"]
                if combined_config.get("ms_password"):
                    combined_config["password"] = combined_config["ms_password"]

            # 特殊处理 API Keys
            api_key = combined_config.get("agent_api_key", "")
            if api_key:
                keys_path = os.path.join(self.src_dir, "keys.json")
                keys_data = {}
                if os.path.exists(keys_path):
                    try:
                        with open(keys_path, 'r') as f:
                            keys_data = json.load(f)
                    except:
                        pass
                
                # 映射到 MindCraft 支持的所有环境变量
                api_keys = [
                    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", 
                    "GOOGLE_API_KEY", "MISTRAL_API_KEY", "GROQ_API_KEY", 
                    "GROQCLOUD_API_KEY", "DEEPSEEK_API_KEY", "XAI_API_KEY", 
                    "QWEN_API_KEY", "REPLICATE_API_KEY", "HUGGINGFACE_API_KEY", 
                    "NOVITA_API_KEY", "OPENROUTER_API_KEY", "GHLF_API_KEY", 
                    "HYPERBOLIC_API_KEY", "CEREBRAS_API_KEY", "MERCURY_API_KEY"
                ]
                for key in api_keys:
                    keys_data[key] = api_key
                
                with open(keys_path, 'w') as f:
                    json.dump(keys_data, f, indent=4)
            
            # 获取端口配置，优先使用用户配置，否则使用默认值 8080
            ms_port = combined_config.get("mindserver_port", 8080)
            try:
                ms_port = int(ms_port)
            except (ValueError, TypeError):
                ms_port = 8080
            
            # 检查端口是否被占用
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                try:
                    s.bind(("0.0.0.0", ms_port))
                except socket.error:
                    logger.error(f"[{self.name}] 启动失败: 端口 {ms_port} 已被占用！请在插件设置中更改端口。")
                    self.logs.append(f"ERROR: Port {ms_port} is already in use. Please change it in settings.")
                    return False
            
            # 记录即将使用的端口
            logger.info(f"[{self.name}] 准备启动 MindServer，端口: {ms_port}")
            self.logs.append(f"Starting MindServer on port {ms_port}...")
            
            # 游戏内 TTS 逻辑
            if "speak" not in combined_config:
                combined_config["speak"] = False
            
            # 将配置通过环境变量传递
            env = os.environ.copy()
            env["MINDSERVER_PORT"] = str(ms_port)
            combined_config["auto_open_ui"] = False
            env["SETTINGS_JSON"] = json.dumps(combined_config)

            cmd = ["node", "main.js"]
            
            # 检查 node 是否可用
            try:
                node_version = subprocess.run(["node", "-v"], capture_output=True, text=True, check=True)
                logger.info(f"[{self.name}] Node 版本: {node_version.stdout.strip()}")
            except Exception as e:
                logger.error(f"[{self.name}] 找不到 Node.js 运行环境: {e}")
                self.logs.append("ERROR: Node.js is not installed or not in PATH.")
                return False

            self._process = subprocess.Popen(
                cmd,
                cwd=self.src_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                env=env,
                encoding='utf-8',
                errors='replace'
            )

            # 启动日志读取线程
            def _read_logs_safe():
                try:
                    self._read_logs()
                except Exception as e:
                    logger.error(f"[{self.name}] 日志读取线程异常: {e}")

            def _read_stderr():
                for line in iter(self._process.stderr.readline, ''):
                    if not line:
                        break
                    clean_line = line.strip()
                    if clean_line:
                        logger.error(f"[{self.name} ERROR] {clean_line}")
                        self.logs.append(f"ERROR: {clean_line}")
                        if len(self.logs) > 500:
                            self.logs.pop(0)

            self._thread = threading.Thread(target=_read_logs_safe, daemon=True)
            self._thread.start()
            
            self._stderr_thread = threading.Thread(target=_read_stderr, daemon=True)
            self._stderr_thread.start()
            
            self.is_active = True
            logger.info(f"[{self.name}] 插件已启动 (PID: {self._process.pid}, 端口: {ms_port})")
            self.logs.append(f"Plugin started successfully (PID: {self._process.pid})")
            return True
        except Exception as e:
            logger.error(f"[{self.name}] 激活插件失败: {e}")
            self.logs.append(f"CRITICAL ERROR: {e}")
            self.is_active = False
            return False

    async def deactivate(self):
        """停止插件进程"""
        if self._process:
            pid = self._process.pid
            try:
                if os.name == 'nt':
                    # Windows 下强制杀死进程树
                    subprocess.run(['taskkill', '/F', '/T', '/PID', str(pid)], capture_output=True)
                else:
                    self._process.terminate()
                    try:
                        self._process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self._process.kill()
            except Exception as e:
                logger.error(f"停止 Minecraft-mindcraft 进程 {pid} 失败: {e}")
            
            self._process = None
        
        # 停止日志线程
        self._thread = None
        self._stderr_thread = None
        
        self.is_active = False
        logger.info("Minecraft-mindcraft 插件已停止")
        return True

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

    def _read_logs(self):
        """读取并解析日志"""
        ms_code_pattern = re.compile(r"enter the code:\s*([A-Z0-9]{8})")
        ms_url_pattern = re.compile(r"go to\s*(https?://[^\s]+)")
        bot_output_pattern = re.compile(r"\[BOT_OUTPUT\] (\{.*\})")
        
        # 使用 activate 时捕获的 loop
        loop = getattr(self, 'loop', None)
        if not loop:
            try:
                loop = asyncio.get_event_loop()
            except RuntimeError:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)

        for line in iter(self._process.stdout.readline, ''):
            if not line:
                break
            clean_line = line.strip()
            if clean_line:
                # 保持日志长度在合理范围内
                self.logs.append(clean_line)
                if len(self.logs) > 500:
                    self.logs.pop(0)
                
                # 解析微软验证码
                code_match = ms_code_pattern.search(clean_line)
                if code_match:
                    self.ms_auth_code = code_match.group(1)
                    logger.info(f"捕获到微软验证码: {self.ms_auth_code}")
                
                url_match = ms_url_pattern.search(clean_line)
                if url_match:
                    self.ms_auth_url = url_match.group(1)
                
                # 解析 Bot 输出并转发到主界面
                bot_output_match = bot_output_pattern.search(clean_line)
                if bot_output_match:
                    try:
                        data = json.loads(bot_output_match.group(1))
                        agent_name = data.get("agentName", "Minecraft AI")
                        message = data.get("message", "")
                        if message:
                            # 安全地在主事件循环中运行协程
                            asyncio.run_coroutine_threadsafe(
                                self._forward_to_ui(agent_name, message),
                                loop
                            )
                    except Exception as e:
                        logger.error(f"解析 Bot 输出失败: {e}")
                
                print(f"[Minecraft-mindcraft] {clean_line}")
                # 确保日志也被记录到 logger 以便调试
                logger.debug(f"Minecraft Log: {clean_line}")

    async def _forward_to_ui(self, agent_name: str, message: str):
        """将 Minecraft 消息转发到主界面并触发前端 TTS"""
        # 检查全局 TTS 开关，决定是否在前端播放
        enable_tts = system_state.get_state("enable_tts", True)
        
        # 构造带前缀的消息
        display_message = f"【Minecraft】{message}"
        
        # 广播到 Live2D/WebSocket 界面
        payload = {
            "type": "chat_message",
            "text": display_message,
            "sender": "chat_normal",
            "senderName": agent_name
        }
        
        # 如果前端开启了 TTS，则生成语音并添加到 payload
        if enable_tts:
            try:
                # 尝试从配置获取 TTS 设置，如果没有则使用默认
                tts_api_key = self.config.get("agent_api_key") or app_settings.SILICONFLOW_API_KEY
                tts_base_url = self.config.get("agent_base_url") or "https://api.siliconflow.cn/v1"
                
                if tts_api_key:
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

    async def get_status(self) -> Dict[str, Any]:
        """获取插件状态，供前端轮询"""
        return {
            "id": self.id,
            "is_active": self.is_active,
            "ms_auth_code": self.ms_auth_code,
            "ms_auth_url": self.ms_auth_url,
            "logs": self.logs[-50:] if self.logs else []
        }

def get_plugin():
    return MinecraftMindcraftPlugin()
