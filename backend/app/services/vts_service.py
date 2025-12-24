import asyncio
import json
import pyvts
import time
from typing import Optional, List, Dict, Any
from app.core.logger import logger

class VTSService:
    def __init__(self):
        self.vts: Optional[pyvts.vts] = None
        self.is_connected = False
        self.last_connect_attempt = 0
        self.retry_interval = 30  # 秒
        self.plugin_info = {
            "plugin_name": "N-T-AI VTS Plugin",
            "developer": "N-T-AI Team",
            "authentication_token_path": "./vts_token.txt",
        }
        self.hotkey_list: List[str] = []

    async def connect(self):
        """连接到 VTube Studio"""
        current_time = time.time()
        if current_time - self.last_connect_attempt < self.retry_interval:
            return
        
        self.last_connect_attempt = current_time
        try:
            self.vts = pyvts.vts(plugin_info=self.plugin_info)
            await self.vts.connect()
            await self.vts.request_authenticate_token()
            await self.vts.request_authenticate()
            self.is_connected = True
            logger.info("[VTS] Connected and authenticated successfully.")
            await self.refresh_hotkeys()
        except Exception as e:
            self.is_connected = False
            logger.error(f"[VTS] Connection failed: {e}")

    async def disconnect(self):
        """断开连接"""
        if self.vts:
            await self.vts.close()
            self.is_connected = False
            logger.info("[VTS] Disconnected.")

    async def refresh_hotkeys(self):
        """刷新热键列表"""
        if not self.is_connected:
            return
        try:
            response = await self.vts.request(self.vts.vts_request.requestHotKeyList())
            self.hotkey_list = [h['name'] for h in response['data']['availableHotkeys']]
            logger.info(f"[VTS] Hotkeys refreshed: {self.hotkey_list}")
        except Exception as e:
            logger.error(f"[VTS] Failed to refresh hotkeys: {e}")

    async def trigger_hotkey(self, hotkey_name: str):
        """触发热键"""
        if not self.is_connected:
            await self.connect()
        if not self.is_connected:
            return
        
        try:
            request = self.vts.vts_request.requestTriggerHotKey(hotkey_name)
            await self.vts.request(request)
            logger.info(f"[VTS] Triggered hotkey: {hotkey_name}")
        except Exception as e:
            logger.error(f"[VTS] Failed to trigger hotkey {hotkey_name}: {e}")

    async def move_model(self, x: float, y: float, size: float = 1.0, rotation: float = 0.0, time: float = 0.5):
        """移动模型"""
        if not self.is_connected:
            await self.connect()
        if not self.is_connected:
            return

        try:
            # 这里的坐标系参考 VTS 官方文档，通常中心是 0,0
            request = self.vts.vts_request.BaseRequest(
                "MoveModelRequest",
                {
                    "timeInSeconds": time,
                    "valuesAreRelativeToModel": False,
                    "positionX": x,
                    "positionY": y,
                    "rotation": rotation,
                    "size": size
                }
            )
            await self.vts.request(request)
            logger.info(f"[VTS] Moved model to ({x}, {y})")
        except Exception as e:
            logger.error(f"[VTS] Failed to move model: {e}")

    async def inject_parameter(self, parameter_name: str, value: float, weight: float = 1.0):
        """注入 Live2D 参数 (例如 FaceAngleX, MouthOpen 等)"""
        if not self.is_connected:
            await self.connect()
        if not self.is_connected:
            return

        try:
            # VTS 注入参数需要先注册自定义参数或直接发送 InjectParameterDataRequest
            request = self.vts.vts_request.BaseRequest(
                "InjectParameterDataRequest",
                {
                    "faceFound": True,
                    "mode": "set", # or "add"
                    "parameterValues": [
                        {
                            "id": parameter_name,
                            "value": value,
                            "weight": weight
                        }
                    ]
                }
            )
            await self.vts.request(request)
        except Exception as e:
            logger.error(f"[VTS] Failed to inject parameter {parameter_name}: {e}")

    async def sync_live2d_data(self, data: Dict[str, float]):
        """同步来自 N-T-AI 的 Live2D 表现数据到 VTS"""
        if not self.is_connected:
            await self.connect()
        if not self.is_connected:
            return

        # 映射关系: N-T-AI -> VTS Standard
        # N-T-AI 的 mouth 0~1, eyes 0~1 (1 为睁眼)
        mapping = {
            "mouth": "MouthOpen",
            "eyes": ["EyeOpenL", "EyeOpenR"],
            "eyebrow": "BrowInnerY",
            "headTilt": "FaceAngleZ",
            "pupilX": "EyeBallX",
            "pupilY": "EyeBallY",
            "blush": "Cheek",  # 常见模型参数名
            "headX": "FaceAngleX",
            "headY": "FaceAngleY"
        }

        parameter_values = []
        for key, val in data.items():
            if key in mapping:
                vts_params = mapping[key]
                if isinstance(vts_params, list):
                    for p in vts_params:
                        parameter_values.append({"id": p, "value": val, "weight": 1.0})
                else:
                    parameter_values.append({"id": vts_params, "value": val, "weight": 1.0})
        
        if not parameter_values:
            return

        try:
            request = self.vts.vts_request.BaseRequest(
                "InjectParameterDataRequest",
                {
                    "faceFound": True,
                    "mode": "set",
                    "parameterValues": parameter_values
                }
            )
            await self.vts.request(request)
        except Exception as e:
            logger.error(f"[VTS] Failed to sync Live2D data to VTS: {e}")

vts_service = VTSService()
