from abc import ABC, abstractmethod
from typing import Dict, Any, Optional

class BasePlugin(ABC):
    """
    Abstract base class for all backend plugins.
    Plugins should inherit from this class and implement the required methods.
    """

    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self.is_active = False
        # Default auto-start behavior
        self.auto_start = True

    @property
    def id(self) -> str:
        """Return the unique ID of the plugin. Defaults to name."""
        return self.name

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the unique name of the plugin."""
        pass

    @property
    def description(self) -> str:
        """Return a brief description of the plugin."""
        return "No description provided."

    async def activate(self) -> bool:
        """Explicitly activate the plugin."""
        try:
            await self.on_startup()
            self.is_active = True
            return True
        except Exception as e:
            print(f"Error activating plugin {self.id}: {e}")
            return False

    async def deactivate(self) -> bool:
        """Explicitly deactivate the plugin."""
        try:
            await self.on_shutdown()
            self.is_active = False
            return True
        except Exception as e:
            print(f"Error deactivating plugin {self.id}: {e}")
            return False

    async def on_startup(self):
        """Called when the application starts or the plugin is enabled."""
        self.is_active = True
        print(f"[{self.name}] Plugin started.")

    async def on_shutdown(self):
        """Called when the application stops or the plugin is disabled."""
        self.is_active = False
        print(f"[{self.name}] Plugin stopped.")

    async def handle_event(self, event_type: str, data: Any) -> Optional[Any]:
        """
        Handle specific events triggered by the core system or other plugins.
        
        Args:
            event_type: String identifier for the event (e.g., "chat_message", "danmaku_received")
            data: Payload associated with the event.
            
        Returns:
            Optional result or None.
        """
        return None

    async def on_config_updated(self) -> None:
        return None
