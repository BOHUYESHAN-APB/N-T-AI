from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from app.services.live2d_service import manager
from app.core.logger import logger

import httpx
from fastapi.responses import HTMLResponse, StreamingResponse
from app.plugins import get_plugin

router = APIRouter(prefix="/plugins/Minecraft-mindcraft", tags=["minecraft"])

class SendMessageRequest(BaseModel):
    agent: str
    message: str
    sender: Optional[str] = "frontend"

class HeadfulActionRequest(BaseModel):
    action: Dict[str, Any]

class HeadfulSkillRequest(BaseModel):
    skill: str
    params: Optional[Dict[str, Any]] = None

@router.post("/config")
async def update_minecraft_config(request_data: Dict[str, Any]):
    """
    更新 Minecraft 插件的配置。
    """
    plugin = get_plugin("Minecraft-mindcraft")
    if not plugin:
        raise HTTPException(status_code=404, detail="Minecraft plugin not found")
    
    # 获取配置数据，处理前端可能发送的 {"config": {...}} 或直接 {...}
    config = request_data.get("config", request_data)
    
    # 更新插件内存中的配置
    plugin.config.update(config)
    
    # 触发插件的配置更新回调（会自动持久化并重启）
    await plugin.on_config_updated()
    
    return {"status": "ok", "config": plugin.config}

@router.api_route("/ui/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"])
async def proxy_minecraft_ui(path: str, request: Request):
    """
    代理 Minecraft 管理页面的请求。
    """
    plugin = get_plugin("Minecraft-mindcraft")
    if not plugin:
        raise HTTPException(status_code=404, detail="Minecraft plugin not found")
    
    # 获取插件配置的端口
    ms_port = plugin.config.get("mindserver_port", 8080)
    
    # 构造目标 URL
    target_url = f"http://localhost:{ms_port}/{path}"
    
    # 转发查询参数
    if request.query_params:
        target_url += f"?{request.query_params}"

    async with httpx.AsyncClient() as client:
        try:
            # 转发请求
            method = request.method
            headers = dict(request.headers)
            # 移除一些可能引起问题的 header
            headers.pop("host", None)
            headers.pop("content-length", None) # 避免长度不匹配
            
            # 读取请求体（如果是 POST）
            content = await request.body()
            
            # 使用 request 预取响应，然后手动流式传输或返回内容
            # 对于 UI 页面，通常不需要 StreamingResponse，直接返回内容更稳妥
            resp = await client.request(
                method,
                target_url,
                headers=headers,
                content=content,
                follow_redirects=True,
                timeout=10.0
            )
            
            from fastapi.responses import Response
            return Response(
                content=resp.content,
                status_code=resp.status_code,
                headers=dict(resp.headers)
            )
        except Exception as e:
            logger.error(f"Proxy error to {target_url}: {e}")
            raise HTTPException(status_code=502, detail=f"Could not connect to MindServer on port {ms_port}")

@router.get("/ui", include_in_schema=False)
async def proxy_minecraft_ui_root(request: Request):
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url=str(request.url).rstrip('/') + '/')

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

@router.post("/send_message")
async def send_message_to_agent(req: SendMessageRequest):
    """
    通过后端转发消息到 MindServer，再由插件送入游戏内对话框。
    这支持前端文本、语音识别文本、语音频道输入的融合。
    """
    plugin = get_plugin("Minecraft-mindcraft")
    if not plugin:
        raise HTTPException(status_code=404, detail="Minecraft plugin not found")
    # headful 模式下通过 WS 直连模组
    if getattr(plugin, "control_mode", "headless") == "headful":
        ok = await plugin.send_headful_message(req.message)
        if ok:
            return {"status": "ok"}
        raise HTTPException(status_code=502, detail="Failed to send headful message")
    ms_port = plugin.config.get("mindserver_port", 8080)
    url = f"http://localhost:{ms_port}/api/send-message"
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, json={"agent": req.agent, "from": req.sender, "message": req.message}, timeout=5.0)
            if resp.status_code == 200:
                return {"status": "ok"}
            else:
                raise HTTPException(status_code=resp.status_code, detail=resp.text)
    except Exception as e:
        logger.error(f"Failed to send message to MindServer: {e}")
        raise HTTPException(status_code=502, detail=str(e))

@router.post("/headful_action")
async def send_headful_action(req: HeadfulActionRequest):
    """
    直接转发 headful 动作 JSON 到本地 Fabric 模组 WS。
    """
    plugin = get_plugin("Minecraft-mindcraft")
    if not plugin:
        raise HTTPException(status_code=404, detail="Minecraft plugin not found")
    if getattr(plugin, "control_mode", "headless") != "headful":
        raise HTTPException(status_code=400, detail="Plugin not in headful mode")
    ok = await plugin.send_headful_action(req.action)
    if ok:
        return {"status": "ok"}
    raise HTTPException(status_code=502, detail="Failed to send headful action")

@router.post("/headful_skill")
async def run_headful_skill(req: HeadfulSkillRequest):
    """
    执行 headful 背包/容器技能（自动装备/整理/合成等）。
    """
    plugin = get_plugin("Minecraft-mindcraft")
    if not plugin:
        raise HTTPException(status_code=404, detail="Minecraft plugin not found")
    if getattr(plugin, "control_mode", "headless") != "headful":
        raise HTTPException(status_code=400, detail="Plugin not in headful mode")
    result = await plugin.run_headful_skill(req.skill, req.params or {})
    if result.get("ok"):
        return {"status": "ok", "result": result}
    raise HTTPException(status_code=400, detail=result)

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
