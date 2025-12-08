from fastapi import APIRouter, HTTPException, Request, Header, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Set
import json
import asyncio
from app.services.motion_agent_service import MotionAgentService
from app.services.llm_service import LLMService

router = APIRouter(prefix="/api/live2d", tags=["live2d"])

# ========== WebSocket 广播管理 ==========
# 存储所有连接的 Live2D WebSocket 客户端
class Live2DConnectionManager:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        print(f"[Live2D WS] Client connected. Total: {len(self.active_connections)}")
    
    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)
        print(f"[Live2D WS] Client disconnected. Total: {len(self.active_connections)}")
    
    async def broadcast(self, message: dict):
        """广播消息到所有连接的客户端"""
        if not self.active_connections:
            return
        
        message_str = json.dumps(message)
        disconnected = set()
        
        for connection in self.active_connections:
            try:
                await connection.send_text(message_str)
            except Exception as e:
                print(f"[Live2D WS] Send failed: {e}")
                disconnected.add(connection)
        
        # 清理断开的连接
        for conn in disconnected:
            self.active_connections.discard(conn)

manager = Live2DConnectionManager()

class MotionRequest(BaseModel):
    user_text: str
    ai_text: str
    emotion: str
    capabilities: Dict[str, List[str]] # {'motions': [], 'expressions': []}

class IdleRequest(BaseModel):
    emotion: str
    capabilities: Dict[str, List[str]]

class ExpressionBroadcastRequest(BaseModel):
    """表情参数广播请求"""
    mouth: float = 0.0
    eyes: float = 1.0
    eyebrow: float = 0.0
    blush: float = 0.0
    pupilX: float = 0.0
    pupilY: float = 0.0
    headTilt: float = 0.0

class MotionBroadcastRequest(BaseModel):
    """动作请求广播"""
    userText: str
    aiText: str

# Initialize services
# Note: In a real app, use dependency injection
llm_service = LLMService()
motion_agent = MotionAgentService(llm_service)

@router.post("/agent/decide")
async def decide_motion(
    request: MotionRequest,
    api_key: Optional[str] = Header(None, alias="X-Motion-Api-Key"),
    base_url: Optional[str] = Header(None, alias="X-Motion-Base-Url"),
    model: Optional[str] = Header(None, alias="X-Motion-Model")
):
    try:
        result = await motion_agent.decide_motion(
            user_text=request.user_text,
            ai_text=request.ai_text,
            emotion=request.emotion,
            capabilities=request.capabilities,
            api_key=api_key,
            base_url=base_url,
            model=model
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/agent/idle")
async def decide_idle(
    request: IdleRequest,
    api_key: Optional[str] = Header(None, alias="X-Motion-Api-Key"),
    base_url: Optional[str] = Header(None, alias="X-Motion-Base-Url"),
    model: Optional[str] = Header(None, alias="X-Motion-Model")
):
    try:
        result = await motion_agent.decide_idle_motion(
            emotion=request.emotion,
            capabilities=request.capabilities,
            api_key=api_key,
            base_url=base_url,
            model=model
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ========== WebSocket 端点 ==========
@router.websocket("/ws")
async def live2d_websocket(websocket: WebSocket):
    """
    Live2D WebSocket 端点
    悬浮窗和侧边栏都可以连接这个端点接收表情/动作指令
    """
    await manager.connect(websocket)
    try:
        while True:
            # 保持连接，等待客户端消息（心跳等）
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                action = message.get('action')
                if action == 'ping':
                    await websocket.send_text(json.dumps({"type": "pong"}))
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"[Live2D WS] Error: {e}")
        manager.disconnect(websocket)

# ========== 广播 HTTP 端点 ==========
@router.post("/broadcast/expression")
async def broadcast_expression(request: ExpressionBroadcastRequest):
    """
    广播表情参数到所有 Live2D 客户端
    Flutter 侧边栏和悬浮窗都会收到
    """
    await manager.broadcast({
        "type": "expression",
        "data": {
            "mouth": request.mouth,
            "eyes": request.eyes,
            "eyebrow": request.eyebrow,
            "blush": request.blush,
            "pupilX": request.pupilX,
            "pupilY": request.pupilY,
            "headTilt": request.headTilt,
        }
    })
    return {"status": "ok", "clients": len(manager.active_connections)}

@router.post("/broadcast/motion")
async def broadcast_motion(request: MotionBroadcastRequest):
    """
    广播动作请求到所有 Live2D 客户端
    客户端会调用 Motion Agent 决策
    """
    await manager.broadcast({
        "type": "motion_request",
        "data": {
            "userText": request.userText,
            "aiText": request.aiText,
        }
    })
    return {"status": "ok", "clients": len(manager.active_connections)}

@router.get("/connections")
async def get_connections():
    """获取当前 WebSocket 连接数"""
    return {"count": len(manager.active_connections)}
