import asyncio
import json
import time
from typing import Any, Callable, Dict, Optional

import websockets


class HeadfulAdapter:
    def __init__(
        self,
        logger,
        log_append: Callable[[str], None],
        on_ready: Callable[[bool], None],
        on_state: Callable[[Optional[Dict[str, Any]]], None],
    ) -> None:
        self._logger = logger
        self._log_append = log_append
        self._on_ready = on_ready
        self._on_state = on_state
        self._ws_task: asyncio.Task | None = None
        self._ws = None
        self._stop_event = asyncio.Event()
        self._last_log = 0.0
        self._send_lock = asyncio.Lock()
        self.ready = False
        self.last_state: Optional[Dict[str, Any]] = None
        self.last_screen: Optional[Dict[str, Any]] = None
        self._screen_waiters: list[asyncio.Future] = []

    async def activate(self, config: Dict[str, Any]) -> bool:
        if self._ws_task and not self._ws_task.done():
            return True
        self._stop_event = asyncio.Event()
        self._ws_task = asyncio.create_task(self._run(config))
        return True

    async def deactivate(self) -> None:
        self._stop_event.set()
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:
                pass
        if self._ws_task is not None:
            self._ws_task.cancel()
            try:
                await self._ws_task
            except Exception:
                pass
        self._ws_task = None
        self._ws = None
        self.ready = False
        self._on_ready(False)

    async def send_message(self, message: str, config: Dict[str, Any]) -> bool:
        if self._ws is None:
            self._log_append("Headful WS not connected; send failed.")
            return False
        payload = {"type": "chat", "message": message}
        if message.startswith("/"):
            payload = {"type": "command", "command": message.lstrip("/")}
        token = (config or {}).get("token", "")
        if token:
            payload["token"] = token
        async with self._send_lock:
            try:
                await self._ws.send(json.dumps(payload, ensure_ascii=False))
                return True
            except Exception as e:
                self._log_append(f"Headful send failed: {e}")
                return False

    async def send_action(self, action: Dict[str, Any], config: Dict[str, Any]) -> bool:
        if self._ws is None:
            self._log_append("Headful WS not connected; action send failed.")
            return False
        if not isinstance(action, dict):
            self._log_append("Headful action invalid: not an object.")
            return False
        if "type" not in action:
            self._log_append("Headful action invalid: missing type.")
            return False
        payload = dict(action)
        token = (config or {}).get("token", "")
        if token and "token" not in payload:
            payload["token"] = token
        async with self._send_lock:
            try:
                await self._ws.send(json.dumps(payload, ensure_ascii=False))
                return True
            except Exception as e:
                self._log_append(f"Headful action send failed: {e}")
                return False

    async def request_screen_snapshot(
        self, config: Dict[str, Any], timeout: float = 2.0
    ) -> Optional[Dict[str, Any]]:
        if self._ws is None:
            self._log_append("Headful WS not connected; screen snapshot failed.")
            return None
        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        self._screen_waiters.append(future)
        ok = await self.send_action({"type": "screenSnapshot"}, config)
        if not ok:
            if not future.done():
                future.cancel()
            try:
                self._screen_waiters.remove(future)
            except ValueError:
                pass
            return None
        try:
            return await asyncio.wait_for(future, timeout=timeout)
        except asyncio.TimeoutError:
            self._log_append("Headful screen snapshot timeout.")
            return None
        finally:
            if not future.done():
                future.cancel()
            try:
                self._screen_waiters.remove(future)
            except ValueError:
                pass

    async def _run(self, config: Dict[str, Any]) -> None:
        backoff = 1
        while not self._stop_event.is_set():
            host = (config or {}).get("host", "127.0.0.1")
            port = (config or {}).get("port", 8765)
            token = (config or {}).get("token", "")
            uri = f"ws://{host}:{port}"
            try:
                self._log_append(f"Headful WS connecting: {uri}")
                async with websockets.connect(uri, max_size=2**20) as ws:
                    self._ws = ws
                    self.ready = True
                    self._on_ready(True)
                    backoff = 1
                    sub = {"type": "subscribe"}
                    if token:
                        sub["token"] = token
                    await ws.send(json.dumps(sub))
                    self._log_append("Headful WS connected and subscribed.")
                    async for message in ws:
                        await self._handle_message(message)
            except Exception as e:
                self.ready = False
                self._on_ready(False)
                self._ws = None
                self._log_append(f"Headful WS error: {e}")
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 10)

    async def _handle_message(self, message: str) -> None:
        try:
            data = json.loads(message)
        except Exception:
            self._log_append(f"Headful WS raw: {message}")
            return

        msg_type = data.get("type")
        if msg_type == "state":
            self.last_state = data
            self._on_state(data)
            now = time.time()
            if now - self._last_log > 1.0:
                self._log_append(
                    f"Headful state: x={data.get('x')} y={data.get('y')} z={data.get('z')}"
                )
                self._last_log = now
        elif msg_type == "event":
            self._log_append(f"Headful event: {data.get('event')}")
        elif msg_type == "hello":
            self._log_append("Headful WS hello received.")
        elif msg_type == "screen_snapshot":
            self.last_screen = data
            if self._screen_waiters:
                waiters = list(self._screen_waiters)
                self._screen_waiters.clear()
                for waiter in waiters:
                    if not waiter.done():
                        waiter.set_result(data)
            handler = data.get("handler")
            screen = data.get("screenClass")
            slots = data.get("slotsCount")
            open_flag = data.get("screenOpen")
            title = data.get("title")
            self._log_append(
                f"Headful screen: {screen or handler} slots={slots} open={open_flag} title={title}"
            )
        elif msg_type == "error":
            self._log_append(f"Headful WS error: {data.get('error')}")
        else:
            self._log_append(f"Headful WS msg: {msg_type}")
