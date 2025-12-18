import platform
import subprocess
import shutil
import asyncio
import os
from typing import Dict, Any, Optional
from ..base import BasePlugin

class LinuxEnvPlugin(BasePlugin):
    """
    Plugin to manage the Virtual Linux Environment.
    Prioritizes Docker for isolation and safety.
    Fallbacks to WSL (Windows) or Native (Linux/Mac) with warnings.
    """
    
    CONTAINER_NAME = "ntai_sandbox_core"
    IMAGE_NAME = "ntai_sandbox_alpine" # Custom Alpine image

    def __init__(self, config: Dict[str, Any] = None):
        super().__init__(config=config)
        self.plugin_dir = os.path.dirname(os.path.abspath(__file__))
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
        
        if self._env_type == "docker":
            await self._ensure_docker_container()

    def _check_environment(self):
        """
        Detects available Linux execution environments.
        Priority: Docker > WSL (Windows) > Native (Linux/Mac)
        """
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
        if platform.system() == "Windows":
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

    async def _ensure_docker_container(self):
        """
        Ensures the sandbox container is running.
        """
        print(f"[{self.name}] Checking Docker container '{self.CONTAINER_NAME}'...")
        
        # Check if running
        check = subprocess.run(
            ["docker", "ps", "--filter", f"name={self.CONTAINER_NAME}", "--format", "{{.Names}}"],
            capture_output=True, text=True
        )
        if self.CONTAINER_NAME in check.stdout.strip():
            print(f"[{self.name}] Container is running.")
            return

        # Check if exists but stopped
        check_stopped = subprocess.run(
            ["docker", "ps", "-a", "--filter", f"name={self.CONTAINER_NAME}", "--format", "{{.Names}}"],
            capture_output=True, text=True
        )
        if self.CONTAINER_NAME in check_stopped.stdout.strip():
            print(f"[{self.name}] Starting existing container...")
            subprocess.run(["docker", "start", self.CONTAINER_NAME], check=True)
            return

        # Check if image exists, if not build it
        image_check = subprocess.run(
            ["docker", "images", "-q", self.IMAGE_NAME],
            capture_output=True, text=True
        )
        
        if not image_check.stdout.strip():
            print(f"[{self.name}] Building Docker image '{self.IMAGE_NAME}' (this may take a while)...")
            try:
                # Run build in the plugin directory where Dockerfile is located
                subprocess.run(
                    ["docker", "build", "-t", self.IMAGE_NAME, "."],
                    cwd=self.plugin_dir,
                    check=True
                )
                print(f"[{self.name}] Image built successfully.")
            except subprocess.CalledProcessError as e:
                print(f"[{self.name}] Failed to build image: {e}")
                self._status = "error"
                return

        # Create and run
        print(f"[{self.name}] Creating new container from {self.IMAGE_NAME}...")
        try:
            subprocess.run(
                ["docker", "run", "-d", "--name", self.CONTAINER_NAME, 
                 "--restart=unless-stopped", 
                 "-p", "6080:6080", # noVNC port mapping
                 self.IMAGE_NAME],
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
                ["docker", "ps", "--filter", f"name={self.CONTAINER_NAME}", "--format", "{{.Names}}"],
                capture_output=True, text=True
            )
            is_running = self.CONTAINER_NAME in check.stdout.strip()
            self._status = "ready" if is_running else "stopped"
            
        return {
            "status": self._status,
            "plugin_detected": self._plugin_detected,
            "type": self._env_type,
            "container": self.CONTAINER_NAME if self._env_type == "docker" else None,
            "vnc_url": "http://localhost:6080/vnc.html" if self._env_type == "docker" and self._status == "ready" else None
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
                # docker exec ntai_sandbox_core bash -c "command"
                cmd_list = ["docker", "exec", self.CONTAINER_NAME, "bash", "-c", command]
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
