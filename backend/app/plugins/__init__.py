from typing import Dict, Any
from .base import BasePlugin
from .linux_env.plugin import LinuxEnvPlugin

# Registry of available plugins
_plugins: Dict[str, BasePlugin] = {}

def register_plugin(plugin: BasePlugin):
    _plugins[plugin.id] = plugin
    print(f"[PluginManager] Registered plugin: {plugin.id} ({plugin.name})")

def get_plugin(id: str) -> BasePlugin | None:
    # 兼容处理 ID，前端可能发送 Minecraft-mindcraft 或 minecraft 或 minecraft_mindcraft
    if id == "minecraft" or id == "minecraft_mindcraft":
        id = "Minecraft-mindcraft"
    return _plugins.get(id)

async def startup_plugins() -> None:
    # 1. Initialize Plugins
    from .bilibili_live import BilibiliLivePlugin
    from .linux_env.plugin import LinuxEnvPlugin
    from app.core.config import settings
    import importlib

    print("[PluginManager] Initializing plugins...")

    # Register Bilibili
    register_plugin(BilibiliLivePlugin())

    # Register Linux Env
    register_plugin(LinuxEnvPlugin())

    # Register Minecraft MindCraft
    try:
        # 使用 importlib 加载带中划线的目录名
        mc_module = importlib.import_module(".Minecraft-mindcraft", package="app.plugins")
        mc_plugin = mc_module.get_plugin()
        # 确保在注册前执行初始化加载配置
        if hasattr(mc_plugin, 'setup'):
            await mc_plugin.setup()
        register_plugin(mc_plugin)
    except Exception as e:
        print(f"[PluginManager] Error registering Minecraft-mindcraft plugin: {e}")

    # 2. Start them
    for plugin in _plugins.values():
        # Check if the plugin should auto-start
        # Can be overridden by individual plugin settings or global config
        # Default auto_start should be taken from the instance property
        should_start = getattr(plugin, "auto_start", True)
        
        # Priority: Config > Default property
        if plugin.config and "auto_start" in plugin.config:
            should_start = plugin.config["auto_start"]
            
        if should_start:
            print(f"[{plugin.name}] Auto-starting...")
            await plugin.on_startup()
        else:
            print(f"[{plugin.name}] Auto-start disabled, skipping startup.")

async def shutdown_plugins() -> None:
    for plugin in _plugins.values():
        await plugin.on_shutdown()
