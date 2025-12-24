from typing import Dict, Any
from .base import BasePlugin
from .linux_env.plugin import LinuxEnvPlugin

# Registry of available plugins
_plugins: Dict[str, BasePlugin] = {}

def register_plugin(plugin: BasePlugin):
    _plugins[plugin.id] = plugin

def get_plugin(id: str) -> BasePlugin | None:
    return _plugins.get(id)

async def startup_plugins() -> None:
    # 1. Initialize Plugins
    from .bilibili_live import BilibiliLivePlugin
    from app.core.config import settings

    # Register Bilibili
    if int(getattr(settings, "BILIBILI_ROOM_ID", 0) or 0) > 0:
        register_plugin(BilibiliLivePlugin(config={"room_id": settings.BILIBILI_ROOM_ID}))

    # Register Linux Env
    register_plugin(LinuxEnvPlugin())

    # Register Minecraft MindCraft
    try:
        import importlib
        # 使用 importlib 加载带中划线的目录名
        mc_module = importlib.import_module(".Minecraft-mindcraft", package="app.plugins")
        register_plugin(mc_module.get_plugin())
    except Exception as e:
        print(f"Error registering Minecraft-mindcraft plugin: {e}")

    # 2. Start them
    for plugin in _plugins.values():
        await plugin.on_startup()

async def shutdown_plugins() -> None:
    for plugin in _plugins.values():
        await plugin.on_shutdown()
