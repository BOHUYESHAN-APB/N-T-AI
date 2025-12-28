import asyncio
import json
import os
import re
import subprocess
import threading
from typing import Any, Callable, Dict


class HeadlessAdapter:
    def __init__(
        self,
        logger,
        src_dir: str,
        log_append: Callable[[str], None],
        on_ms_auth_code: Callable[[str | None], None],
        on_ms_auth_url: Callable[[str | None], None],
        on_bot_output: Callable[[str, str], Any],
    ) -> None:
        self._logger = logger
        self._src_dir = src_dir
        self._log_append = log_append
        self._on_ms_auth_code = on_ms_auth_code
        self._on_ms_auth_url = on_ms_auth_url
        self._on_bot_output = on_bot_output
        self._process = None
        self._thread = None
        self._stderr_thread = None
        self._loop = None

    async def activate(self, config: Dict[str, Any]) -> bool:
        combined_config = dict(config or {})
        host = combined_config.get("host", "127.0.0.1")
        port = combined_config.get("port", 25565)
        self._logger.info(f"[Headless] activating... target: {host}:{port}")
        self._log_append(f"Activating plugin... Target server: {host}:{port}")

        try:
            self._loop = asyncio.get_running_loop()
        except RuntimeError:
            self._loop = asyncio.get_event_loop()

        self._on_ms_auth_code(None)
        self._on_ms_auth_url(None)

        try:
            if not os.path.exists(self._src_dir):
                self._logger.error(f"[Headless] source dir missing: {self._src_dir}")
                self._log_append(f"ERROR: Source directory not found: {self._src_dir}")
                return False

            main_js_path = os.path.join(self._src_dir, "main.js")
            if not os.path.exists(main_js_path):
                self._logger.error(f"[Headless] entry not found: {main_js_path}")
                self._log_append(f"ERROR: Entry file not found: {main_js_path}")
                return False

            node_modules_path = os.path.join(self._src_dir, "node_modules")
            if not os.path.exists(node_modules_path):
                self._logger.warning("[Headless] node_modules not found")
                self._log_append("WARNING: node_modules not found. Please run 'npm install' in the plugin/src directory.")

            if combined_config.get("agent_name") and combined_config.get("auth") == "offline":
                combined_config["username"] = combined_config["agent_name"]

            if combined_config.get("auth") == "microsoft":
                if combined_config.get("ms_email"):
                    combined_config["username"] = combined_config["ms_email"]
                if combined_config.get("ms_password"):
                    combined_config["password"] = combined_config["ms_password"]

            api_key = combined_config.get("agent_api_key", "")
            if api_key:
                keys_path = os.path.join(self._src_dir, "keys.json")
                keys_data = {}
                if os.path.exists(keys_path):
                    try:
                        with open(keys_path, "r") as f:
                            keys_data = json.load(f)
                    except Exception:
                        pass

                api_keys = [
                    "OPENAI_API_KEY",
                    "ANTHROPIC_API_KEY",
                    "GEMINI_API_KEY",
                    "GOOGLE_API_KEY",
                    "MISTRAL_API_KEY",
                    "GROQ_API_KEY",
                    "GROQCLOUD_API_KEY",
                    "DEEPSEEK_API_KEY",
                    "XAI_API_KEY",
                    "QWEN_API_KEY",
                    "REPLICATE_API_KEY",
                    "HUGGINGFACE_API_KEY",
                    "NOVITA_API_KEY",
                    "OPENROUTER_API_KEY",
                    "GHLF_API_KEY",
                    "HYPERBOLIC_API_KEY",
                    "CEREBRAS_API_KEY",
                    "MERCURY_API_KEY",
                ]
                for key in api_keys:
                    keys_data[key] = api_key

                with open(keys_path, "w") as f:
                    json.dump(keys_data, f, indent=4)

            ms_port = combined_config.get("mindserver_port", 8080)
            try:
                ms_port = int(ms_port)
            except (ValueError, TypeError):
                ms_port = 8080

            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                try:
                    s.bind(("0.0.0.0", ms_port))
                except socket.error:
                    self._logger.error(f"[Headless] port {ms_port} already in use")
                    self._log_append(f"ERROR: Port {ms_port} is already in use. Please change it in settings.")
                    return False

            self._logger.info(f"[Headless] starting MindServer on port: {ms_port}")
            self._log_append(f"Starting MindServer on port {ms_port}...")

            if "speak" not in combined_config:
                combined_config["speak"] = False

            env = os.environ.copy()
            env["MINDSERVER_PORT"] = str(ms_port)
            combined_config["auto_open_ui"] = False
            env["SETTINGS_JSON"] = json.dumps(combined_config)

            cmd = ["node", "main.js"]
            try:
                node_version = subprocess.run(["node", "-v"], capture_output=True, text=True, check=True)
                self._logger.info(f"[Headless] Node version: {node_version.stdout.strip()}")
            except Exception as e:
                self._logger.error(f"[Headless] Node.js not found: {e}")
                self._log_append("ERROR: Node.js is not installed or not in PATH.")
                return False

            creation_flags = 0
            if os.name == "nt" and hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
                creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP

            self._process = subprocess.Popen(
                cmd,
                cwd=self._src_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.PIPE,
                text=True,
                bufsize=1,
                env=env,
                encoding="utf-8",
                errors="replace",
                creationflags=creation_flags,
            )

            self._thread = threading.Thread(target=self._read_logs_safe, daemon=True)
            self._thread.start()

            self._stderr_thread = threading.Thread(target=self._read_stderr, daemon=True)
            self._stderr_thread.start()

            self._logger.info(f"[Headless] process started (PID: {self._process.pid})")
            self._log_append(f"Plugin started successfully (PID: {self._process.pid})")
            return True
        except Exception as e:
            self._logger.error(f"[Headless] activation failed: {e}")
            self._log_append(f"CRITICAL ERROR: {e}")
            return False

    async def deactivate(self) -> bool:
        if not self._process:
            return True
        pid = self._process.pid
        try:
            try:
                if self._process.stdin:
                    self._process.stdin.close()
            except Exception:
                pass
            if os.name == "nt":
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
                try:
                    self._process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
            else:
                self._process.terminate()
                try:
                    self._process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self._process.kill()
        except Exception as e:
            self._logger.error(f"[Headless] stop process {pid} failed: {e}")
        finally:
            try:
                if self._process.stdout:
                    self._process.stdout.close()
            except Exception:
                pass
            try:
                if self._process.stderr:
                    self._process.stderr.close()
            except Exception:
                pass
        self._process = None

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)
        if self._stderr_thread and self._stderr_thread.is_alive():
            self._stderr_thread.join(timeout=2)
        self._thread = None
        self._stderr_thread = None
        return True

    def _read_logs_safe(self) -> None:
        try:
            self._read_logs()
        except Exception as e:
            self._logger.error(f"[Headless] log thread failed: {e}")

    def _read_stderr(self) -> None:
        if not self._process or not self._process.stderr:
            return
        for line in iter(self._process.stderr.readline, ""):
            if not line:
                break
            clean_line = line.strip()
            if clean_line:
                self._logger.error(f"[Headless ERROR] {clean_line}")
                self._log_append(f"ERROR: {clean_line}")

    def _read_logs(self) -> None:
        if not self._process or not self._process.stdout:
            return
        ms_code_pattern = re.compile(r"enter the code:\s*([A-Z0-9]{8})")
        ms_url_pattern = re.compile(r"go to\s*(https?://[^\s]+)")
        bot_output_pattern = re.compile(r"\[BOT_OUTPUT\] (\{.*\})")

        loop = self._loop
        if not loop:
            try:
                loop = asyncio.get_event_loop()
            except RuntimeError:
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)

        for line in iter(self._process.stdout.readline, ""):
            if not line:
                break
            clean_line = line.strip()
            if clean_line:
                self._logger.debug(f"[MC-Plugin-Raw] {clean_line}")
                self._log_append(clean_line)

                code_match = ms_code_pattern.search(clean_line)
                if code_match:
                    self._on_ms_auth_code(code_match.group(1))
                    self._logger.info(f"[Headless] captured ms code: {code_match.group(1)}")

                url_match = ms_url_pattern.search(clean_line)
                if url_match:
                    self._on_ms_auth_url(url_match.group(1))

                bot_output_match = bot_output_pattern.search(clean_line)
                if bot_output_match:
                    try:
                        data = json.loads(bot_output_match.group(1))
                        agent_name = data.get("agentName", "Minecraft AI")
                        message = data.get("message", "")
                        if message and loop:
                            asyncio.run_coroutine_threadsafe(
                                self._on_bot_output(agent_name, message),
                                loop,
                            )
                    except Exception as e:
                        self._logger.error(f"[Headless] parse BOT_OUTPUT failed: {e}")

                print(f"[Minecraft-mindcraft] {clean_line}")
                self._logger.debug(f"Minecraft Log: {clean_line}")
