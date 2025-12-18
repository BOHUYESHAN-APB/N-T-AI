from typing import Dict, Any
from ..base import BasePlugin
from .linux_env.plugin import LinuxEnvPlugin

# Registry of available plugins
_plugins: Dict[str, BasePlugin] = {}

def register_plugin(plugin: BasePlugin):
    _plugins[plugin.name] = plugin

def get_plugin(name: str) -> BasePlugin | None:
    return _plugins.get(name)

async def startup_plugins() -> None:
    # 1. Initialize Plugins
    from .bilibili_live import BilibiliLivePlugin
    from app.core.config import settings

    # Register Bilibili
    register_plugin(BilibiliLivePlugin(config={"room_id": settings.BILIBILI_ROOM_ID}))

    # Register Linux Env
    register_plugin(LinuxEnvPlugin())

    # 2. Start them
    for plugin in _plugins.values():
        await plugin.on_startup()

async def shutdown_plugins() -> None:
    for plugin in _plugins.values():
        await plugin.on_shutdown()
