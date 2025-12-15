from fastapi import APIRouter, HTTPException, Request, Header, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Set
import json
import asyncio
import base64
import os
import time
import uuid
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
    history: Optional[List[Dict[str, str]]] = None # Context history

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
    history: Optional[List[Dict[str, str]]] = None

class AudioBroadcastRequest(BaseModel):
    """音频广播请求"""
    audio: str # Base64 encoded audio

class ChatBroadcastRequest(BaseModel):
    """Chat message broadcast request"""
    text: str
    sender: str = "chat_normal" # user, chat_normal, chat_sc, agent
    senderName: Optional[str] = None

# Initialize services
# Note: In a real app, use dependency injection
llm_service = LLMService()
motion_agent = MotionAgentService(llm_service)

@router.post("/agent/decide")
async def decide_motion(
    request: MotionRequest,
    api_key: Optional[str] = Header(None, alias="X-Motion-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header(None, alias="X-Motion-Base-Url"),
    model: Optional[str] = Header(None, alias="X-Motion-Model")
):
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    try:
        result = await motion_agent.decide_motion(
            user_text=request.user_text,
            ai_text=request.ai_text,
            emotion=request.emotion,
            capabilities=request.capabilities,
            history=request.history,
            api_key=final_api_key,
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
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header(None, alias="X-Motion-Base-Url"),
    model: Optional[str] = Header(None, alias="X-Motion-Model")
):
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    try:
        result = await motion_agent.decide_idle_motion(
            emotion=request.emotion,
            capabilities=request.capabilities,
            api_key=final_api_key,
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
                elif action == 'text_input':
                    text = message.get('text')
                    enable_thinking = message.get('enable_thinking', False)
                    enable_search = message.get('enable_search', False)
                    
                    if text:
                        print(f"[Live2D WS] Processing text input: {text[:50]}... (Thinking: {enable_thinking})")
                        
                        # Lazy import to avoid circular dependency
                        from app.services.chat_service import ChatService
                        chat_service = ChatService()
                        
                        # Process message (async)
                        # Note: This will block the WebSocket loop until completion. 
                        # For production, consider using a background task or separate queue.
                        response_text = await chat_service.process_message(
                            message=text,
                            user_id="live2d_websocket_user",
                            enable_thinking=enable_thinking,
                            enable_search=enable_search,
                            enable_backend_tts=True # Enable TTS for Live2D
                        )
                        
                        # Send final response back to this client specifically?
                        # chat_service already broadcasts 'gemini_response' via manager.broadcast
                        # So we don't need to send it again here manually, unless we want a private reply.
                        # But live2d architecture seems to rely on broadcast.
                        
                else:
                    print(f"[Live2D WS] Received message: {action}")
            except json.JSONDecodeError:
                print(f"[Live2D WS] Invalid JSON received: {data}")
                pass
    except WebSocketDisconnect as e:
        print(f"[Live2D WS] Disconnect code: {e.code}, reason: {e.reason}")
        manager.disconnect(websocket)
    except Exception as e:
        print(f"[Live2D WS] Error: {e}")
        import traceback
        traceback.print_exc()
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
async def broadcast_motion(
    request: MotionBroadcastRequest,
    api_key: Optional[str] = Header(None, alias="X-Motion-Api-Key"),
    base_url: Optional[str] = Header(None, alias="X-Motion-Base-Url"),
    model: Optional[str] = Header(None, alias="X-Motion-Model")
):
    """
    广播动作请求到所有 Live2D 客户端
    客户端会调用 Motion Agent 决策
    """
    data = {
        "userText": request.userText,
        "aiText": request.aiText,
        "history": request.history or [],
    }
    
    # 将配置信息透传给前端
    if api_key:
        data["apiKey"] = api_key
    if base_url:
        data["baseUrl"] = base_url
    if model:
        data["model"] = model
        
    await manager.broadcast({
        "type": "motion_request",
        "data": data
    })
    return {"status": "ok", "clients": len(manager.active_connections)}

@router.post("/broadcast/chat")
async def broadcast_chat(request: ChatBroadcastRequest):
    """
    Broadcast a chat message (from live stream, user, or other agents)
    """
    await manager.broadcast({
        "type": "chat_message",
        "text": request.text,
        "sender": request.sender,
        "senderName": request.senderName
    })
    return {"status": "ok", "clients": len(manager.active_connections)}

@router.post("/broadcast/audio")
async def broadcast_audio(request: AudioBroadcastRequest):
    """
    Broadcast audio to all Live2D clients for lip-sync.
    Optimized: Saves Base64 to file and broadcasts URL to reduce WebSocket overhead.
    """
    client_count = len(manager.active_connections)
    if client_count > 0:
        try:
            start_at = time.time()
            # 1. Decode Base64
            audio_data = base64.b64decode(request.audio)
            
            # 2. Ensure temp directory exists
            temp_dir = "app/static/live2d/temp"
            os.makedirs(temp_dir, exist_ok=True)
            
            # 3. Save to file (unique name)
            filename = f"tts_{uuid.uuid4().hex}.mp3"
            file_path = os.path.join(temp_dir, filename)
            
            with open(file_path, "wb") as f:
                f.write(audio_data)
                
            # 4. Construct URL (assuming /live2d maps to app/static/live2d)
            # Need to check main.py static mount. Usually /static maps to app/static.
            # If we mount /static/live2d as /live2d, then:
            audio_url = f"/static/live2d/temp/{filename}"
            
            # 5. Broadcast URL
            await manager.broadcast({
                "type": "audio",
                "data": {
                    "url": audio_url,
                    "start_at": start_at
                }
            })
            
            print(f"[Live2D] Broadcasted audio URL: {audio_url} to {client_count} clients.")
            
            # 6. Cleanup old files (older than 5 minutes)
            try:
                current_time = time.time()
                for f in os.listdir(temp_dir):
                    fp = os.path.join(temp_dir, f)
                    if os.path.isfile(fp) and current_time - os.path.getmtime(fp) > 300:
                        os.remove(fp)
            except Exception as e:
                print(f"[Live2D] Cleanup warning: {e}")
                
            return {"status": "ok", "clients": client_count, "url": audio_url}
            
        except Exception as e:
            print(f"[Live2D] Audio broadcast error: {e}")
            # Fallback to base64 if file save fails
            await manager.broadcast({
                "type": "audio",
                "data": {
                    "audio": request.audio
                }
            })
            return {"status": "ok", "clients": client_count, "fallback": True}
    else:
        print("[Live2D] No clients connected for audio broadcast.")
        return {"status": "no_clients", "clients": 0}

@router.get("/connections")
async def get_connections():
    """获取当前 WebSocket 连接数"""
    return {"count": len(manager.active_connections)}
