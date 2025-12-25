from typing import Dict, Any

class SystemStateManager:
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(SystemStateManager, cls).__new__(cls)
            cls._instance.state = {
                "enable_tts": True,  # 默认开启
            }
        return cls._instance

    def update_state(self, key: str, value: Any):
        self.state[key] = value

    def get_state(self, key: str, default: Any = None):
        return self.state.get(key, default)

system_state = SystemStateManager()
