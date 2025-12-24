import os
import subprocess
import threading
import re
import json
import logging
import asyncio
from typing import Dict, Any, List, Optional
from ..base import BasePlugin

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
        """初始化插件配置"""
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
                "language": "zh"
            }
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(default_config, f, indent=4)
        return True

    async def activate(self):
        """启动插件进程"""
        if self.is_active:
            return True
        
        try:
            # 将配置通过环境变量传递
            env = os.environ.copy()
            
            # 基础配置
            combined_config = {}
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    combined_config = json.load(f)
            
            # 合并来自后端的实时配置
            combined_config.update(self.config)
            
            # 特殊处理 API Keys (如果提供了)
            if combined_config.get("agent_api_key"):
                # 我们可以创建一个临时 keys.json 或者直接通过环境变量/代码修改
                # MindCraft 默认读取 keys.json，我们需要确保它能拿到 key
                keys_path = os.path.join(self.src_dir, "keys.json")
                keys_data = {}
                if os.path.exists(keys_path):
                    with open(keys_path, 'r') as f:
                        keys_data = json.load(f)
                
                # 简单映射：目前我们先支持通用 provider 逻辑
                # 这里可以根据 provider 进一步细化
                keys_data["OPENAI_API_KEY"] = combined_config["agent_api_key"]
                # ... 其他 key 映射
                
                with open(keys_path, 'w') as f:
                    json.dump(keys_data, f, indent=4)

            env["SETTINGS_JSON"] = json.dumps(combined_config)

            cmd = ["node", "main.js"]
            self._process = subprocess.Popen(
                cmd,
                cwd=self.src_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                encoding='utf-8',
                errors='replace',
                env=env
            )
            
            self.is_active = True
            self._thread = threading.Thread(target=self._read_logs, daemon=True)
            self._thread.start()
            logger.info(f"Minecraft-mindcraft 插件已启动 (PID: {self._process.pid})")
            return True
        except Exception as e:
            logger.error(f"启动 Minecraft-mindcraft 失败: {e}")
            self.is_active = False
            return False

    async def deactivate(self):
        """停止插件进程"""
        if self._process:
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
        self.is_active = False
        logger.info("Minecraft-mindcraft 插件已停止")
        return True

    def _read_logs(self):
        """读取并解析日志"""
        ms_code_pattern = re.compile(r"enter the code:\s*([A-Z0-9]{8})")
        ms_url_pattern = re.compile(r"go to\s*(https?://[^\s]+)")
        
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
                
                print(f"[Minecraft-mindcraft] {clean_line}")

    async def get_status(self) -> Dict[str, Any]:
        """获取插件状态，供前端轮询"""
        return {
            "id": self.id,
            "is_active": self.is_active,
            "ms_auth_code": self.ms_auth_code,
            "ms_auth_url": self.ms_auth_url,
            "logs": self.logs[-50:] if self.logs else []
        }

    async def on_config_updated(self, config: Dict[str, Any] = None):
        """当配置更新时（通常来自 Flutter 端）"""
        if config:
            # 写入新配置到文件
            if os.path.exists(self.config_path):
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    json.dump(config, f, indent=4)
        
        if self.is_active:
            logger.info(f"Plugin {self.id} config updated, restarting...")
            await self.deactivate()
            await self.activate()

def get_plugin():
    return MinecraftMindcraftPlugin()
