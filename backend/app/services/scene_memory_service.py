import threading
import time
from typing import Any, Dict, List, Optional


class SceneMemoryService:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._store: Dict[str, Dict[str, Any]] = {}

    def update_scene(
        self,
        *,
        session_id: Optional[str],
        user_id: Optional[str],
        context: Optional[str],
        tasks: Optional[List[str]],
        ttl_sec: Optional[float] = None,
    ) -> None:
        key = (session_id or "").strip() or (user_id or "").strip()
        if not key:
            return
        cleaned_context = (context or "").strip()
        cleaned_tasks = [t.strip() for t in (tasks or []) if t and t.strip()]
        if not cleaned_context and not cleaned_tasks:
            self.clear_scene(session_id=session_id, user_id=user_id)
            return
        expires_at = None
        if ttl_sec is not None:
            try:
                ttl = float(ttl_sec)
                if ttl > 0:
                    expires_at = time.time() + ttl
            except Exception:
                expires_at = None
        with self._lock:
            self._store[key] = {
                "context": cleaned_context,
                "tasks": cleaned_tasks,
                "updated_at": time.time(),
                "expires_at": expires_at,
            }

    def get_scene(self, *, session_id: Optional[str], user_id: Optional[str]) -> Dict[str, Any]:
        key = (session_id or "").strip() or (user_id or "").strip()
        if not key:
            return {}
        now = time.time()
        with self._lock:
            data = self._store.get(key)
            if not data:
                return {}
            expires_at = data.get("expires_at")
            if isinstance(expires_at, (int, float)) and expires_at > 0 and now > expires_at:
                self._store.pop(key, None)
                return {}
            return dict(data)

    def clear_scene(self, *, session_id: Optional[str], user_id: Optional[str]) -> None:
        key = (session_id or "").strip() or (user_id or "").strip()
        if not key:
            return
        with self._lock:
            self._store.pop(key, None)


scene_memory_service = SceneMemoryService()
