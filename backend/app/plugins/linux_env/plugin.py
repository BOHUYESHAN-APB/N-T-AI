import platform
import subprocess
import shutil
import asyncio
import os
import json
import locale
from typing import Dict, Any, Optional
from ..base import BasePlugin

class LinuxEnvPlugin(BasePlugin):
    """
    Plugin to manage the Virtual Linux Environment.
    Prioritizes Docker for isolation and safety.
    Fallbacks to WSL (Windows) or Native (Linux/Mac) with warnings.
    """
    
    DEFAULT_CONTAINER_NAME = "ntai_sandbox_core"
    DEFAULT_IMAGE_NAME = "ntai_sandbox_alpine" # Custom Alpine image
    DEFAULT_VNC_URL = "http://localhost:6080/vnc.html"

    def __init__(self, config: Dict[str, Any] = None):
        super().__init__(config=config)
        self.plugin_dir = os.path.dirname(os.path.abspath(__file__))
        self.config_path = os.path.join(self.plugin_dir, "settings.json")
        self.config = self._load_config(config)
        self._apply_config()
        self._status = "unknown"
        self._env_type = "none" # docker, wsl, native, none
        self._plugin_detected = False
        self._check_environment()

    @property
    def name(self) -> str:
        return "linux_env"

    @property
    def description(self) -> str:
        return "Virtual Linux Sandbox (Docker > WSL > Native)"

    async def on_startup(self) -> None:
        await super().on_startup()
        self._check_environment()
        print(f"[{self.name}] Environment Type: {self._env_type}")
        
        if self._env_type == "docker" and self._auto_start_container:
            await self._ensure_docker_container()

    def _default_config(self) -> Dict[str, Any]:
        return {
            "auto_start": False,
            "disable_wsl": False,
            "docker": {
                "image_name": self.DEFAULT_IMAGE_NAME,
                "container_name": self.DEFAULT_CONTAINER_NAME,
                "vnc_url": self.DEFAULT_VNC_URL,
                "download_url": "",
                "auto_start_container": False,
                "start_on_demand": True,
            },
        }

    def _merge_config(self, base: Dict[str, Any], update: Dict[str, Any]) -> Dict[str, Any]:
        merged = dict(base)
        for key, value in (update or {}).items():
            if key == "docker" and isinstance(value, dict):
                current_docker = merged.get("docker") or {}
                merged["docker"] = {**current_docker, **value}
            else:
                merged[key] = value
        return merged

    def _load_config(self, override: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        config = self._default_config()
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                if isinstance(loaded, dict):
                    config = self._merge_config(config, loaded)
            except Exception as e:
                print(f"[{self.name}] Failed to load config: {e}")
        if override:
            config = self._merge_config(config, override)
        return config

    def _save_config(self) -> None:
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self.config, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"[{self.name}] Failed to save config: {e}")

    def _apply_config(self) -> None:
        self.auto_start = bool(self.config.get("auto_start", False))
        self._disable_wsl = bool(self.config.get("disable_wsl", False))
        docker_cfg = self.config.get("docker") or {}
        self._image_name = docker_cfg.get("image_name") or self.DEFAULT_IMAGE_NAME
        self._container_name = docker_cfg.get("container_name") or self.DEFAULT_CONTAINER_NAME
        self._vnc_url = docker_cfg.get("vnc_url") or self.DEFAULT_VNC_URL
        self._download_url = docker_cfg.get("download_url") or ""
        self._auto_start_container = bool(docker_cfg.get("auto_start_container", False))
        self._start_on_demand = bool(docker_cfg.get("start_on_demand", True))

    def _check_environment(self):
        """
        Detects available Linux execution environments.
        Priority: Docker > WSL (Windows) > Native (Linux/Mac)
        """
        disable_wsl = bool(self._disable_wsl)
        # 1. Check for Docker
        if shutil.which("docker"):
            # Verify docker is actually running (daemon)
            try:
                subprocess.run(["docker", "info"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._env_type = "docker"
                self._plugin_detected = True
                self._status = "ready"
                return
            except subprocess.CalledProcessError:
                # Docker installed but daemon might be down
                pass

        # 2. Check for WSL (Windows only)
        if platform.system() == "Windows" and not disable_wsl:
            if shutil.which("wsl"):
                self._env_type = "wsl"
                self._plugin_detected = True
                self._status = "ready"
                return

        # 3. Check Native (Linux/Mac)
        if platform.system() in ["Linux", "Darwin"]:
            self._env_type = "native"
            self._plugin_detected = True
            self._status = "ready"
            return
            
        self._env_type = "none"
        self._status = "not_found"

    async def on_config_updated(self) -> None:
        self._apply_config()
        self._save_config()
        self._check_environment()
        return None

    async def _ensure_docker_container(self):
        """
        Ensures the sandbox container is running.
        """
        print(f"[{self.name}] Checking Docker container '{self._container_name}'...")
        
        # Check if running
        check = subprocess.run(
            ["docker", "ps", "--filter", f"name={self._container_name}", "--format", "{{.Names}}"],
            capture_output=True, text=True
        )
        if self._container_name in check.stdout.strip():
            print(f"[{self.name}] Container is running.")
            return

        # Check if exists but stopped
        check_stopped = subprocess.run(
            ["docker", "ps", "-a", "--filter", f"name={self._container_name}", "--format", "{{.Names}}"],
            capture_output=True, text=True
        )
        if self._container_name in check_stopped.stdout.strip():
            print(f"[{self.name}] Starting existing container...")
            subprocess.run(["docker", "start", self._container_name], check=True)
            return

        # Check if image exists, if not build it
        image_check = subprocess.run(
            ["docker", "images", "-q", self._image_name],
            capture_output=True, text=True
        )
        
        if not image_check.stdout.strip():
            print(f"[{self.name}] Building Docker image '{self._image_name}' (this may take a while)...")
            
            # Detect Locale for Mirror Selection
            use_china_mirror = "false"
            try:
                # Basic locale check (e.g. 'zh_CN', 'Chinese')
                sys_lang = locale.getdefaultlocale()[0]
                if sys_lang and "zh" in sys_lang.lower():
                    use_china_mirror = "true"
                    print(f"[{self.name}] Detected Chinese locale. Using Tsinghua Mirrors.")
            except Exception:
                pass

            try:
                # Run build in the plugin directory where Dockerfile is located
                subprocess.run(
                    ["docker", "build", 
                     "--build-arg", f"USE_CHINA_MIRROR={use_china_mirror}",
                     "-t", self._image_name, "."],
                    cwd=self.plugin_dir,
                    check=True
                )
                print(f"[{self.name}] Image built successfully.")
            except subprocess.CalledProcessError as e:
                print(f"[{self.name}] Failed to build image: {e}")
                self._status = "error"
                return

        # Create and run
        print(f"[{self.name}] Creating new container from {self._image_name}...")
        try:
            subprocess.run(
                ["docker", "run", "-d", "--name", self._container_name, 
                 "--restart=unless-stopped", 
                 "-p", "6080:6080", # noVNC port mapping
                 self._image_name],
                check=True
            )
            print(f"[{self.name}] Container started successfully.")
            
        except subprocess.CalledProcessError as e:
            print(f"[{self.name}] Failed to start Docker container: {e}")
            self._status = "error"

    def get_status(self) -> Dict[str, Any]:
        # Re-check status on request (lightweight)
        if self._env_type == "docker":
            # Check if container is actually running
            check = subprocess.run(
                ["docker", "ps", "--filter", f"name={self._container_name}", "--format", "{{.Names}}"],
                capture_output=True, text=True
            )
            is_running = self._container_name in check.stdout.strip()
            self._status = "ready" if is_running else "stopped"
            
        return {
            "status": self._status,
            "plugin_detected": self._plugin_detected,
            "type": self._env_type,
            "container": self._container_name if self._env_type == "docker" else None,
            "vnc_url": self._vnc_url if self._env_type == "docker" and self._status == "ready" else None
        }

    async def execute_command(self, command: str) -> Dict[str, Any]:
        """
        Executes a command in the detected environment.
        """
        if not self._plugin_detected:
            return {"success": False, "error": "No virtual Linux environment detected."}

        try:
            cmd_list = []
            if self._env_type == "docker":
                if self.get_status().get("status") != "ready" and self._start_on_demand:
                    await self._ensure_docker_container()
                if self.get_status().get("status") != "ready":
                    return {"success": False, "error": "Docker sandbox is not running."}
                # docker exec ntai_sandbox_core bash -c "command"
                # Use --user ntai if needed, but container already runs as ntai
                cmd_list = ["docker", "exec", self._container_name, "bash", "-c", command]
            elif self._env_type == "wsl":
                # wsl -e bash -c "command"
                cmd_list = ["wsl", "-e", "bash", "-c", command]
            elif self._env_type == "native":
                # bash -c "command"
                cmd_list = ["bash", "-c", command]
            else:
                return {"success": False, "error": "Unknown environment type."}

            result = subprocess.run(
                cmd_list,
                capture_output=True,
                text=True,
                check=False
            )
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
                "env": self._env_type
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
