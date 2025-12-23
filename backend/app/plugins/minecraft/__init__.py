import os
import asyncio
import subprocess
import threading
import json
import shutil
import urllib.request
import zipfile
from typing import Any, Dict, Optional
from ..base import BasePlugin

class MinecraftPlugin(BasePlugin):
    """
    Plugin for integrating Minecraft bots using MindCraft or Mineflayer.
    Exclusive choice: Only one can be active at a time.
    Supports bundled or system-installed Node.js.
    """

    def __init__(self, config: Dict[str, Any] | None = None) -> None:
        super().__init__(config=config)
        self._process: Optional[subprocess.Popen] = None
        self._log_thread: Optional[threading.Thread] = None
        
        # 基础路径
        self.minecraft_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "src"))
        self.mindcraft_path = os.path.join(self.minecraft_root, "mindcraft-develop")
        self.mineflayer_path = os.path.join(self.minecraft_root, "mineflayer-master")
        
        # Node.js 路径配置
        self.bin_dir = os.path.abspath(os.path.join(os.getcwd(), "bin"))
        self.node_dir = os.path.join(self.bin_dir, "node")
        self.node_exe = os.path.join(self.node_dir, "node.exe") if os.name == 'nt' else os.path.join(self.node_dir, "bin", "node")

    def _get_node_command(self) -> str:
        """获取可用的 Node.js 命令路径"""
        # 1. 优先检查内置路径
        if os.path.exists(self.node_exe):
            return self.node_exe
        
        # 2. 检查系统路径
        system_node = shutil.which("node")
        if system_node:
            return system_node
            
        return ""

    async def _ensure_node_runtime(self) -> bool:
        """确保 Node.js 环境可用，如果缺失则尝试下载"""
        node_cmd = self._get_node_command()
        if node_cmd:
            return True

        print(f"[{self.name}] Node.js runtime not found. Attempting to download portable version...")
        try:
            os.makedirs(self.node_dir, exist_ok=True)
            # 这里以 Windows x64 为例，实际可根据系统动态调整
            # 注意：官方链接可能会随版本更新，这里仅作为逻辑演示
            url = "https://nodejs.org/dist/v20.11.1/node-v20.11.1-win-x64.zip"
            zip_path = os.path.join(self.bin_dir, "node.zip")
            
            # 下载
            print(f"[{self.name}] Downloading Node.js from {url}...")
            urllib.request.urlretrieve(url, zip_path)
            
            # 解压
            print(f"[{self.name}] Extracting Node.js...")
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(self.bin_dir)
            
            # 整理目录结构（将解压出的文件夹重命名为 node）
            extracted_folder = os.path.join(self.bin_dir, "node-v20.11.1-win-x64")
            if os.path.exists(extracted_folder):
                if os.path.exists(self.node_dir):
                    shutil.rmtree(self.node_dir)
                os.rename(extracted_folder, self.node_dir)
            
            # 清理 zip
            os.remove(zip_path)
            print(f"[{self.name}] Node.js runtime installed successfully.")
            return True
        except Exception as e:
            print(f"[{self.name}] Failed to download Node.js: {e}")
            return False

    @property
    def name(self) -> str:
        return "minecraft"

    @property
    def description(self) -> str:
        return "Integration for Minecraft AI agents (MindCraft) or basic bots (Mineflayer)."

    async def on_startup(self) -> None:
        await super().on_startup()
        
        # 确保运行时环境
        if not await self._ensure_node_runtime():
            print(f"[{self.name}] Cannot start: Node.js runtime missing.")
            return

        # 默认使用 mindcraft，如果配置中指定了 mineflayer 则切换
        mode = self.config.get("mode", "mindcraft").lower()
        
        if mode == "mindcraft":
            await self._start_mindcraft()
        elif mode == "mineflayer":
            await self._start_mineflayer()
        else:
            print(f"[{self.name}] Unknown mode: {mode}. Defaulting to MindCraft.")
            await self._start_mindcraft()

    async def on_shutdown(self) -> None:
        await super().on_shutdown()
        self._stop_process()

    def _stop_process(self):
        if self._process:
            print(f"[{self.name}] Stopping Minecraft subprocess...")
            self._process.terminate()
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
        self.is_active = False

    def _log_reader(self):
        if not self._process or not self._process.stdout:
            return
        for line in iter(self._process.stdout.readline, ''):
            if not line: break
            print(f"[Minecraft-Subprocess] {line.strip()}")

    async def _start_mindcraft(self) -> None:
        print(f"[{self.name}] Starting MindCraft mode...")
        node_cmd = self._get_node_command()
        if not node_cmd:
            print(f"[{self.name}] Error: Node.js command not found.")
            return

        # 检查 main.js 是否存在
        init_script = os.path.join(self.mindcraft_path, "main.js")
        if not os.path.exists(init_script):
            print(f"[{self.name}] Error: MindCraft main.js not found at {init_script}")
            return

        # 检查 node_modules 是否存在，如果不存在且 npm 可用，则尝试安装
        node_modules = os.path.join(self.mindcraft_path, "node_modules")
        if not os.path.exists(node_modules):
            print(f"[{self.name}] node_modules not found, attempting npm install...")
            try:
                npm_cmd = "npm"
                if node_cmd == self.node_exe:
                    npm_exe = os.path.join(self.node_dir, "npm.cmd") if os.name == 'nt' else os.path.join(self.node_dir, "bin", "npm")
                    if os.path.exists(npm_exe):
                        npm_cmd = npm_exe
                
                subprocess.run([npm_cmd, "install"], cwd=self.mindcraft_path, check=True, shell=True)
            except Exception as e:
                print(f"[{self.name}] npm install failed: {e}. Please run 'npm install' manually in {self.mindcraft_path}")
        
        try:
            # 准备环境变量，传递配置
            from app.core.config import settings as app_settings
            env = os.environ.copy()
            
            # 复用主脑配置
            env["OPENAI_API_KEY"] = app_settings.OPENAI_API_KEY
            env["OPENAI_BASE_URL"] = app_settings.OPENAI_BASE_URL
            env["NTAI_BACKEND_URL"] = f"http://localhost:{os.getenv('PORT', '23456')}/v1"
            
            # 如果配置了其他的 key 也可以传递
            # env["GEMINI_API_KEY"] = ...
            
            settings_json = {
                "mindserver_port": self.config.get("mindserver_port", 8080),
                "auto_open_ui": False,
                "host": self.config.get("mc_host", "127.0.0.1"),
                "port": self.config.get("mc_port", 25565),
                "auth": self.config.get("mc_auth", "offline"),
                "username": self.config.get("mc_user", ""),
                "password": self.config.get("mc_pass", ""),
                "base_profile": self.config.get("mc_base_profile", "assistant"),
                "language": self.config.get("mc_language", "zh"),
                "minecraft_version": self.config.get("mc_version", "auto"),
                "allow_vision": self.config.get("allow_vision", False),
                "allow_insecure_coding": self.config.get("allow_insecure_coding", False),
                "chat_ingame": self.config.get("chat_ingame", True),
                "speak": self.config.get("speak", False),
            }
            env["SETTINGS_JSON"] = json.dumps(settings_json)

            # 启动 mindcraft
            self._process = subprocess.Popen(
                [node_cmd, "main.js"],
                cwd=self.mindcraft_path,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                shell=True,
                env=env
            )
            self._start_log_thread()
            self.is_active = True
        except Exception as e:
            print(f"[{self.name}] Failed to start MindCraft: {e}")

    async def _start_mineflayer(self) -> None:
        print(f"[{self.name}] Starting Mineflayer mode...")
        node_cmd = self._get_node_command()
        if not node_cmd:
            print(f"[{self.name}] Error: Node.js command not found.")
            return

        # 寻找示例脚本
        example_script = os.path.join(self.mineflayer_path, "examples", "echo.js")
        if not os.path.exists(example_script):
             examples_dir = os.path.join(self.mineflayer_path, "examples")
             if os.path.exists(examples_dir):
                 files = os.listdir(examples_dir)
                 js_files = [f for f in files if f.endswith('.js')]
                 if js_files:
                     example_script = os.path.join(examples_dir, js_files[0])
        
        if not os.path.exists(example_script):
            print(f"[{self.name}] Error: No mineflayer example found.")
            return

        # 检查 node_modules
        node_modules = os.path.join(self.mineflayer_path, "node_modules")
        if not os.path.exists(node_modules):
            print(f"[{self.name}] node_modules not found, attempting npm install...")
            try:
                npm_cmd = "npm"
                if node_cmd == self.node_exe:
                    npm_exe = os.path.join(self.node_dir, "npm.cmd") if os.name == 'nt' else os.path.join(self.node_dir, "bin", "npm")
                    if os.path.exists(npm_exe):
                        npm_cmd = npm_exe
                subprocess.run([npm_cmd, "install"], cwd=self.mineflayer_path, check=True, shell=True)
            except Exception as e:
                print(f"[{self.name}] npm install failed: {e}")

        try:
            self._process = subprocess.Popen(
                [node_cmd, example_script],
                cwd=self.mineflayer_path,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                shell=True
            )
            self._start_log_thread()
            self.is_active = True
        except Exception as e:
            print(f"[{self.name}] Failed to start Mineflayer: {e}")

    def _start_log_thread(self):
        self._log_thread = threading.Thread(target=self._log_reader, daemon=True)
        self._log_thread.start()

    async def on_config_updated(self) -> None:
        """Called when config is updated from the frontend."""
        print(f"[{self.name}] Config updated, restarting with new settings...")
        self._stop_process()
        
        mode = self.config.get("mode", "mindcraft").lower()
        if mode == "mindcraft":
            await self._start_mindcraft()
        elif mode == "mineflayer":
            await self._start_mineflayer()
        else:
            await self._start_mindcraft()

    async def handle_event(self, event_type: str, data: Any) -> Optional[Any]:
        if event_type == "minecraft_command":
            goal = data.get("goal")
            if not goal:
                return {"status": "error", "message": "Missing goal"}
            
            # Try to send the command to the MindCraft server
            port = self.config.get("mindserver_port", 8080)
            url = f"http://localhost:{port}/api/command"
            
            try:
                import httpx
                async with httpx.AsyncClient(timeout=5) as client:
                    resp = await client.post(url, json={"goal": goal})
                    if resp.status_code == 200:
                        print(f"[{self.name}] Successfully sent goal to MindCraft: {goal}")
                        return {"status": "received"}
                    else:
                        print(f"[{self.name}] Failed to send goal: {resp.text}")
                        return {"status": "error", "message": resp.text}
            except Exception as e:
                print(f"[{self.name}] Error sending goal to MindCraft: {e}")
                return {"status": "error", "message": str(e)}
                
        return None
