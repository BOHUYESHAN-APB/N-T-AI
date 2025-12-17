from typing import Dict, Optional

from .base import BasePlugin
from .bilibili_live import BilibiliLivePlugin
from app.core.config import settings

_plugins: Dict[str, BasePlugin] = {
    "bilibili_live": BilibiliLivePlugin(config={"room_id": settings.BILIBILI_ROOM_ID}),
}


def get_plugin(name: str) -> Optional[BasePlugin]:
    return _plugins.get(name)


async def startup_plugins() -> None:
    for plugin in _plugins.values():
        await plugin.on_startup()


async def shutdown_plugins() -> None:
    for plugin in _plugins.values():
        await plugin.on_shutdown()

