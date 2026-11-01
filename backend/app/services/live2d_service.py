from fastapi import WebSocket
from starlette.websockets import WebSocketState
from typing import Set
import json
from app.core.logger import logger

class Live2DConnectionManager:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        logger.info(f"[Live2D WS] Client connected. Total: {len(self.active_connections)}")
    
    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)
        logger.info(f"[Live2D WS] Client disconnected. Total: {len(self.active_connections)}")
    
    async def broadcast(self, message: dict):
        """广播消息到所有连接的客户端"""
        if not self.active_connections:
            return
        
        message_str = json.dumps(message)
        disconnected = set()
        
        for connection in self.active_connections:
            if connection.client_state != WebSocketState.CONNECTED or connection.application_state != WebSocketState.CONNECTED:
                disconnected.add(connection)
                continue
            try:
                await connection.send_text(message_str)
            except Exception as e:
                err_text = str(e)
                if "websocket.send" in err_text or "response already completed" in err_text:
                    disconnected.add(connection)
                    continue
                logger.error(f"[Live2D WS] Send failed: {e}")
                disconnected.add(connection)
        
        # 清理断开的连接
        for conn in disconnected:
            self.active_connections.discard(conn)

manager = Live2DConnectionManager()
