from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from app.services.live2d_service import manager
from app.core.logger import logger

router = APIRouter(prefix="/plugins/minecraft", tags=["minecraft"])

class MinecraftEvent(BaseModel):
    type: str
    agent: str
    message: str
    data: Optional[Dict[str, Any]] = None

class MinecraftPOVFrame(BaseModel):
    agent: str
    image: str  # base64 encoded image
    stats: Optional[Dict[str, Any]] = None

@router.post("/event")
async def handle_minecraft_event(event: MinecraftEvent):
    """
    接收来自 Minecraft 代理的事件，并将其广播到前端界面。
    """
    # logger.info(f"[Minecraft Event] {event.agent}: {event.message}")
    
    if event.type == "chat":
        # 广播到前端的 Live2D WebSocket，以便在聊天界面显示
        # 我们使用 sender: "minecraft" 让前端识别
        await manager.broadcast({
            "type": "chat_message",
            "text": event.message,
            "sender": "minecraft",
            "senderName": event.agent
        })
    elif event.type == "status":
        # 广播状态更新
        await manager.broadcast({
            "type": "minecraft_status",
            "agent": event.agent,
            "message": event.message,
            "data": event.data
        })
    
    return {"status": "ok"}

@router.post("/pov")
async def handle_minecraft_pov(frame: MinecraftPOVFrame):
    """
    接收来自 Minecraft 代理的第一视角画面，并将其广播到前端界面。
    """
    await manager.broadcast({
        "type": "minecraft_pov",
        "agent": frame.agent,
        "image": frame.image,
        "stats": frame.stats
    })
    return {"status": "ok"}

@router.get("/stream", response_class=HTMLResponse)
async def get_minecraft_stream():
    """
    返回一个专门用于 OBS 捕获的全屏推流页面。
    """
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Minecraft AI POV Stream</title>
        <style>
            body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: black; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
            #stream { width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
            #status-bar { position: absolute; bottom: 20px; left: 50%; transform: translateX(-50%); display: flex; flex-direction: column; align-items: center; gap: 5px; background: rgba(0,0,0,0.5); padding: 10px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.2); backdrop-filter: blur(5px); }
            .stats-row { display: flex; gap: 15px; color: white; font-size: 14px; text-shadow: 1px 1px 2px black; }
            .stat-item { display: flex; align-items: center; gap: 5px; }
            .health-bar { color: #ff4d4d; font-weight: bold; }
            .food-bar { color: #ffa366; font-weight: bold; }
            .pos-info { color: #aaa; font-size: 12px; }
            #status-top { position: absolute; top: 10px; left: 10px; color: #00ff00; font-family: monospace; text-shadow: 1px 1px 2px black; }
            .live-badge { background: red; color: white; padding: 2px 5px; border-radius: 3px; font-weight: bold; margin-right: 5px; animation: blink 1s infinite; }
            @keyframes blink { 0% { opacity: 1; } 50% { opacity: 0.5; } 100% { opacity: 1; } }
            .held-item { background: rgba(255,255,255,0.1); padding: 2px 8px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.3); }
        </style>
    </head>
    <body>
        <div id="status-top"><span class="live-badge">LIVE</span> <span id="agent-name">Waiting for stream...</span></div>
        <img id="stream" src="" />
        <div id="status-bar">
            <div class="stats-row">
                <div class="stat-item health-bar">❤️ <span id="hp">20</span>/20</div>
                <div class="stat-item food-bar">🍖 <span id="food">20</span>/20</div>
                <div class="stat-item">⚔️ <span id="held-item" class="held-item">None</span></div>
            </div>
            <div class="pos-info">XYZ: <span id="pos">0, 0, 0</span></div>
        </div>
        <script>
            const streamImg = document.getElementById('stream');
            const agentName = document.getElementById('agent-name');
            const hpText = document.getElementById('hp');
            const foodText = document.getElementById('food');
            const heldItemText = document.getElementById('held-item');
            const posText = document.getElementById('pos');

            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}/live2d/ws`;
            
            function connect() {
                const ws = new WebSocket(wsUrl);
                ws.onmessage = (event) => {
                    const data = JSON.parse(event.data);
                    if (data.type === 'minecraft_pov') {
                        streamImg.src = 'data:image/jpeg;base64,' + data.image;
                        agentName.innerText = data.agent;
                        
                        if (data.stats) {
                            hpText.innerText = Math.round(data.stats.health || 0);
                            foodText.innerText = Math.round(data.stats.food || 0);
                            heldItemText.innerText = data.stats.heldItem || 'None';
                            if (data.stats.pos) {
                                posText.innerText = `${Math.round(data.stats.pos.x)}, ${Math.round(data.stats.pos.y)}, ${Math.round(data.stats.pos.z)}`;
                            }
                        }
                    }
                };
                ws.onclose = () => {
                    agentName.innerText = 'Disconnected. Reconnecting...';
                    setTimeout(connect, 2000);
                };
                ws.onerror = (err) => {
                    console.error('WebSocket Error:', err);
                };
            }
            connect();
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)
