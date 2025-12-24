from fastapi import APIRouter, HTTPException, Request, Header, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Set
from collections import deque
import json
import asyncio
import base64
import os
import time
import uuid
from app.services.motion_agent_service import MotionAgentService
from app.services.llm_service import LLMService
from app.services.audio_service import AudioService
from app.services.vts_service import vts_service
from app.core.config import settings
import io
import wave

router = APIRouter(prefix="/api/live2d", tags=["live2d"])

from app.services.priority_manager import priority_manager, ChatPriority
from app.services.live2d_service import manager

# ========== WebSocket 广播管理 ==========
# Live2DConnectionManager is now in app.services.live2d_service

_last_motion_broadcast_ts: float = 0.0
_last_motion_broadcast_key: str = ""
_scheduled_chat_tasks: Dict[str, asyncio.Task] = {}

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

class ScheduleChatRequest(BaseModel):
    delay_ms: int = 0
    prompt: str
    user_id: str = "live2d_websocket_user"
    enable_backend_tts: bool = True
    enable_thinking: bool = False
    enable_search: bool = False
    tts_mode: str = "sentence"

class CancelScheduledChatRequest(BaseModel):
    task_id: str

class VoiceChannelRequest(BaseModel):
    channel_id: str
    is_active: bool = True

class VoiceChannelTranscriptRequest(BaseModel):
    channel_id: str
    text: str
    speaker: Optional[str] = None
    respond: bool = True
    user_id: str = "live2d_websocket_user"

# Initialize services
# Note: In a real app, use dependency injection
llm_service = LLMService()
motion_agent = MotionAgentService(llm_service)

class ProactiveChatRequest(BaseModel):
    enabled: bool

@router.post("/agent/proactive_chat")
async def toggle_proactive_chat(request: ProactiveChatRequest):
    priority_manager.set_proactive_chat(request.enabled)
    return {"status": "ok", "enabled": request.enabled}

class VTSHotkeyRequest(BaseModel):
    hotkey: str

class VTSMoveRequest(BaseModel):
    x: float
    y: float
    size: float = 1.0
    rotation: float = 0.0
    time: float = 0.5

class VTSParameterRequest(BaseModel):
    name: str
    value: float
    weight: float = 1.0

@router.post("/vts/connect")
async def vts_connect():
    await vts_service.connect()
    return {"status": "ok", "connected": vts_service.is_connected}

@router.post("/vts/hotkey")
async def vts_trigger_hotkey(request: VTSHotkeyRequest):
    await vts_service.trigger_hotkey(request.hotkey)
    return {"status": "ok"}

@router.post("/vts/move")
async def vts_move_model(request: VTSMoveRequest):
    await vts_service.move_model(request.x, request.y, request.size, request.rotation, request.time)
    return {"status": "ok"}

@router.post("/vts/parameter")
async def vts_inject_parameter(request: VTSParameterRequest):
    await vts_service.inject_parameter(request.name, request.value, request.weight)
    return {"status": "ok"}

@router.get("/vts/hotkeys")
async def vts_get_hotkeys():
    await vts_service.refresh_hotkeys()
    return {"hotkeys": vts_service.hotkey_list}

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
    session_mode: str = "idle"
    last_user_activity_ts = time.time()

    audio_service = AudioService()
    audio_sample_rate = 16000
    audio_channels = 1
    audio_pcm_buffer = bytearray()
    audio_pre_roll = deque(maxlen=6)
    speaking = False
    silence_frames = 0
    noise_floor = 80.0
    last_voice_ts = time.time()
    auto_close_sent = False
    stt_lock = asyncio.Lock()

    def _pcm16_to_wav_bytes(pcm_bytes: bytes, sample_rate: int, channels: int) -> bytes:
        bio = io.BytesIO()
        with wave.open(bio, "wb") as wf:
            wf.setnchannels(int(channels))
            wf.setsampwidth(2)
            wf.setframerate(int(sample_rate))
            wf.writeframes(pcm_bytes)
        return bio.getvalue()

    async def _process_utterance(pcm_bytes: bytes):
        if not pcm_bytes:
            return
        stt_api_key = (getattr(settings, "STT_API_KEY", "") or "").strip()
        stt_base_url = (getattr(settings, "STT_BASE_URL", "") or "").strip()
        stt_model = (getattr(settings, "STT_MODEL", "") or "FunAudioLLM/SenseVoiceSmall").strip()
        if not stt_api_key or not stt_base_url:
            return

        async with stt_lock:
            try:
                wav_bytes = _pcm16_to_wav_bytes(pcm_bytes, audio_sample_rate, audio_channels)
            except Exception:
                return

            try:
                transcript = await audio_service.transcribe(
                    file_obj=wav_bytes,
                    filename="utterance.wav",
                    api_key=stt_api_key,
                    base_url=stt_base_url,
                    model=stt_model,
                )
            except Exception:
                return

            transcript = (transcript or "").strip()
            if not transcript:
                return

            await manager.broadcast(
                {
                    "type": "user_transcript",
                    "text": transcript,
                    "isNewMessage": True,
                }
            )

            await priority_manager.add_task(
                priority=ChatPriority.USER,
                message=transcript,
                user_id="live2d_websocket_user",
                enable_thinking=False,
                enable_search=False,
                enable_backend_tts=True,
            )

    def _reset_audio_state():
        nonlocal audio_pcm_buffer, audio_pre_roll, speaking, silence_frames, noise_floor, last_voice_ts, auto_close_sent
        audio_pcm_buffer = bytearray()
        audio_pre_roll.clear()
        speaking = False
        silence_frames = 0
        noise_floor = 80.0
        last_voice_ts = time.time()
        auto_close_sent = False

    try:
        while True:
            try:
                packet = await websocket.receive()
            except (WebSocketDisconnect, RuntimeError):
                break
            
            if "text" in packet and packet["text"] is not None:
                data = packet["text"]
                try:
                    message = json.loads(data)
                except json.JSONDecodeError:
                    print(f"[Live2D WS] Invalid JSON received: {data}")
                    continue

                action = message.get("action")
                if action == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
                    continue

                if action == "start_session":
                    input_type = (message.get("input_type") or "").strip().lower()
                    if input_type not in ["audio", "text"]:
                        input_type = "text"
                    session_mode = input_type
                    last_user_activity_ts = time.time()
                    if session_mode == "audio":
                        _reset_audio_state()
                    await websocket.send_text(json.dumps({"type": "session_started", "input_mode": session_mode}))
                    continue

                if action == "end_session":
                    session_mode = "idle"
                    _reset_audio_state()
                    await websocket.send_text(json.dumps({"type": "session_ended"}))
                    continue

                if action == "text_input":
                    text = message.get("text")
                    enable_thinking = message.get("enable_thinking", False)
                    enable_search = message.get("enable_search", False)
                    if text:
                        last_user_activity_ts = time.time()
                        await priority_manager.add_task(
                            priority=ChatPriority.USER,
                            message=text,
                            user_id="live2d_websocket_user",
                            enable_thinking=enable_thinking,
                            enable_search=enable_search,
                            enable_backend_tts=True,
                        )
                    continue

                if action == "proactive_chat":
                    if not bool(getattr(settings, "PROACTIVE_IDLE_ENABLED", True)):
                        continue
                    idle_sec = float(getattr(settings, "PROACTIVE_IDLE_MIN_SEC", 45) or 45)
                    if (time.time() - float(last_user_activity_ts or 0.0)) < idle_sec:
                        continue
                    
                    await priority_manager.add_task(
                        priority=ChatPriority.PROACTIVE,
                        message="空闲时请你主动说一句话，口语化一点，短一些，可以带点口癖，并顺便抛一个轻问题。",
                        user_id="live2d_websocket_user",
                        enable_thinking=False,
                        enable_search=False,
                        enable_backend_tts=True,
                    )
                    last_user_activity_ts = time.time()
                    continue

                if action == "voice_channel_transcript":
                    channel_id = (message.get("channel_id") or "").strip()
                    text = (message.get("text") or "").strip()
                    speaker = (message.get("speaker") or "").strip()
                    respond = bool(message.get("respond", True))
                    if channel_id and text:
                        await manager.broadcast(
                            {
                                "type": "voice_channel_transcript",
                                "channel_id": channel_id,
                                "speaker": speaker or None,
                                "text": text,
                            }
                        )
                        prefix = f"【语音频道 {channel_id}】"
                        if speaker:
                            prefix += f"{speaker}: "
                        else:
                            prefix += " "
                        await manager.broadcast(
                            {
                                "type": "chat_message",
                                "text": prefix + text,
                                "sender": "agent",
                            }
                        )
                        if respond:
                            await priority_manager.add_task(
                                priority=ChatPriority.VOICE_CH,
                                message=prefix + text,
                                user_id="live2d_websocket_user",
                                enable_thinking=False,
                                enable_search=False,
                                enable_backend_tts=True,
                            )
                    continue

                print(f"[Live2D WS] Received message: {action}")
                continue

            if "bytes" in packet and packet["bytes"] is not None:
                if session_mode != "audio":
                    continue
                chunk = packet["bytes"]
                if not isinstance(chunk, (bytes, bytearray)) or len(chunk) < 2:
                    continue

                mv = memoryview(chunk)
                if len(mv) % 2 != 0:
                    continue
                try:
                    samples = mv.cast("h")
                except TypeError:
                    continue
                if len(samples) == 0:
                    continue

                sum_abs = 0.0
                for s in samples:
                    if s < 0:
                        sum_abs += -float(s)
                    else:
                        sum_abs += float(s)
                mean_abs = sum_abs / float(len(samples))

                dynamic_threshold = max(200.0, float(noise_floor) * 4.0)
                is_voice = mean_abs > dynamic_threshold

                if not is_voice:
                    noise_floor = (noise_floor * 0.96) + (mean_abs * 0.04)
                    if noise_floor < 20.0:
                        noise_floor = 20.0

                now = time.time()

                if is_voice:
                    last_voice_ts = now
                    last_user_activity_ts = now
                    if not speaking:
                        speaking = True
                        silence_frames = 0
                        try:
                            await manager.broadcast({"type": "user_activity"})
                        except Exception:
                            pass
                        for fr in list(audio_pre_roll):
                            audio_pcm_buffer.extend(fr)
                        audio_pre_roll.clear()
                    audio_pcm_buffer.extend(chunk)
                    if (len(audio_pcm_buffer) / 2.0) >= (audio_sample_rate * 12.0):
                        pcm_copy = bytes(audio_pcm_buffer)
                        _reset_audio_state()
                        asyncio.create_task(_process_utterance(pcm_copy))
                else:
                    if speaking:
                        silence_frames += 1
                        audio_pcm_buffer.extend(chunk)
                        if silence_frames >= 10:
                            pcm_copy = bytes(audio_pcm_buffer)
                            _reset_audio_state()
                            asyncio.create_task(_process_utterance(pcm_copy))
                    else:
                        audio_pre_roll.append(bytes(chunk))

                if not auto_close_sent:
                    idle_limit = float(getattr(settings, "PROACTIVE_IDLE_MIN_SEC", 45) or 45)
                    if (now - float(last_voice_ts or now)) > max(20.0, idle_limit):
                        auto_close_sent = True
                        try:
                            await websocket.send_text(json.dumps({"type": "auto_close_mic", "message": "长时间无语音输入，已自动关闭麦克风"}))
                        except Exception:
                            pass
                continue
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
    
    global _last_motion_broadcast_ts, _last_motion_broadcast_key
    try:
        now = time.time()
        key = json.dumps(
            {
                "userText": data.get("userText", ""),
                "aiText": data.get("aiText", ""),
                "historyLen": len(data.get("history") or []),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
        if key == _last_motion_broadcast_key and (now - float(_last_motion_broadcast_ts or 0.0)) < 0.5:
            return {"status": "ok", "clients": len(manager.active_connections), "deduped": True}
        _last_motion_broadcast_key = key
        _last_motion_broadcast_ts = now
    except Exception:
        pass
    
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

@router.post("/agent/schedule_chat")
async def schedule_chat(request: ScheduleChatRequest):
    task_id = str(uuid.uuid4())
    delay_ms = int(request.delay_ms or 0)
    if delay_ms < 0:
        delay_ms = 0

    async def _run():
        try:
            if delay_ms:
                await asyncio.sleep(delay_ms / 1000.0)
            from app.services.chat_service import ChatService

            chat_service = ChatService()
            await chat_service.process_message(
                message=request.prompt,
                user_id=request.user_id,
                enable_thinking=bool(request.enable_thinking),
                enable_search=bool(request.enable_search),
                enable_backend_tts=bool(request.enable_backend_tts),
                tts_mode=request.tts_mode,
            )
        finally:
            _scheduled_chat_tasks.pop(task_id, None)

    _scheduled_chat_tasks[task_id] = asyncio.create_task(_run())
    return {"status": "ok", "task_id": task_id, "delay_ms": delay_ms}

@router.post("/agent/cancel_scheduled_chat")
async def cancel_scheduled_chat(request: CancelScheduledChatRequest):
    task_id = (request.task_id or "").strip()
    task = _scheduled_chat_tasks.pop(task_id, None)
    if not task:
        return {"status": "not_found", "task_id": task_id}
    try:
        task.cancel()
    except Exception:
        pass
    return {"status": "ok", "task_id": task_id}

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
            
            ext = "mp3"
            if len(audio_data) >= 12 and audio_data[0:4] == b"RIFF" and audio_data[8:12] == b"WAVE":
                ext = "wav"

            # 3. Save to file (unique name)
            filename = f"tts_{uuid.uuid4().hex}.{ext}"
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

@router.post("/agent/voice_channel_monitor")
async def voice_channel_monitor(request: VoiceChannelRequest):
    await manager.broadcast(
        {
            "type": "voice_channel_update",
            "channel_id": request.channel_id,
            "is_active": bool(request.is_active),
        }
    )
    return {"status": "ok", "clients": len(manager.active_connections)}

@router.post("/agent/voice_channel_transcript")
async def voice_channel_transcript(request: VoiceChannelTranscriptRequest):
    text = (request.text or "").strip()
    if not text:
        return {"status": "empty", "clients": len(manager.active_connections)}

    payload = {
        "type": "voice_channel_transcript",
        "channel_id": request.channel_id,
        "speaker": request.speaker,
        "text": text,
    }
    await manager.broadcast(payload)

    if bool(request.respond):
        from app.services.chat_service import ChatService
        chat_service = ChatService()
        speaker = (request.speaker or "").strip()
        prefix = f"【语音频道 {request.channel_id}】"
        if speaker:
            prefix += f"{speaker}: "
        else:
            prefix += " "
        await chat_service.process_message(
            message=prefix + text,
            user_id=(request.user_id or "live2d_websocket_user"),
            enable_thinking=False,
            enable_search=False,
            enable_backend_tts=True,
            tts_mode="sentence",
        )

    return {"status": "ok", "clients": len(manager.active_connections)}
