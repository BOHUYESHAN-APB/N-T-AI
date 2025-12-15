from fastapi import FastAPI, HTTPException, Request, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from typing import List, Optional, Union
import asyncio
import json
import time
import os
from urllib.parse import unquote
from contextlib import asynccontextmanager
from app.core.config import settings
from app.models.database import create_db_and_tables
from app.services.chat_service import ChatService
from app.core.logger import logger
from app.core.logger import get_recent_errors, set_recent_error_max
from app.api.routes import memory_routes, model_routes, live2d_routes, audio_routes
from app.plugins import startup_plugins, shutdown_plugins, get_plugin
from app.plugins.bilibili_live import BilibiliLivePlugin

# Lifecycle manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up Astra-Me Backend...")
    create_db_and_tables()
    await startup_plugins()
    try:
        yield
    finally:
        logger.info("Shutting down Astra-Me Backend...")
        await shutdown_plugins()

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan
)


# --- Certificate Info Endpoint (for clients to fetch current cert/fingerprint)
@app.get("/internal/certificates")
async def get_certificates():
    """Return current server certificate PEM and SHA256 fingerprint(s).
    Use this to allow clients to perform certificate pinning.
    """
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes
    except Exception:
        return {"error": "cryptography not installed"}

    cert_path = settings.SSL_CERT_PATH
    if not cert_path or not os.path.exists(cert_path):
        return {"error": "no_certificate"}

    try:
        with open(cert_path, "rb") as f:
            pem = f.read()
        cert = x509.load_pem_x509_certificate(pem)
        fp = cert.fingerprint(hashes.SHA256())
        # Fingerprint as hex colon-separated
        fp_hex = ':'.join(['%02X' % b for b in fp])
        return {"pem": pem.decode('utf-8'), "sha256_fingerprint": fp_hex}
    except Exception as e:
        logger.error(f"Failed to read cert: {e}")
        return {"error": str(e)}

# Include Memory Dashboard Routes
app.include_router(memory_routes.router)
app.include_router(model_routes.router)
app.include_router(live2d_routes.router)
app.include_router(audio_routes.router, prefix="/api/audio", tags=["audio"])

# Mount static files for Live2D/3D renderer
static_dir = os.path.join(os.path.dirname(__file__), "app", "static")
if not os.path.exists(static_dir):
    os.makedirs(static_dir)
app.mount("/static", StaticFiles(directory=static_dir), name="static")

# --- OpenAI Compatible Models ---

class OpenAIMessage(BaseModel):
    role: str
    content: Union[str, List[dict]]

class OpenAIRequest(BaseModel):
    model: str = "default"
    messages: List[OpenAIMessage]
    stream: bool = False
    temperature: Optional[float] = 0.7
    user: Optional[str] = "default_user"

class OpenAIChoice(BaseModel):
    index: int
    message: OpenAIMessage
    finish_reason: str = "stop"

class OpenAIResponse(BaseModel):
    id: str = "chatcmpl-123"
    object: str = "chat.completion"
    created: int = int(time.time())
    model: str = "astra-me-v1"
    choices: List[OpenAIChoice]
    usage: dict = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    # Custom extension for N-T-AI
    emotion: Optional[str] = None 

class EmbeddingRequest(BaseModel):
    input: Union[str, List[str]]
    model: str = "text-embedding-ada-002"

chat_service = ChatService()
_frontend_recent_errors = []


class PluginConfigUpdate(BaseModel):
    config: dict = Field(default_factory=dict)


class DanmakuItem(BaseModel):
    user: str
    content: str
    price: Optional[float] = None
    timestamp: Optional[float] = None


class DanmakuBatchRequest(BaseModel):
    items: list[DanmakuItem]


class BilibiliEvent(BaseModel):
    room_id: str
    user: str
    content: str
    price: Optional[float] = None
    kind: str = "danmaku"
    timestamp: Optional[float] = None

class FrontendLogItem(BaseModel):
    timestamp: float
    level: str
    message: str
    exception: str | None = None

class FrontendLogs(BaseModel):
    errors: list[FrontendLogItem] = []
    max: int | None = None

@app.post("/v1/embeddings")
async def create_embeddings(request: EmbeddingRequest, raw_request: Request):
    target_api_key = raw_request.headers.get("X-Target-Api-Key")
    target_base_url = raw_request.headers.get("X-Target-Base-Url")
    
    text_input = request.input
    if isinstance(text_input, list):
        text_input = text_input[0] 
        
    embedding = await chat_service.llm.get_embedding(text_input, api_key=target_api_key, base_url=target_base_url)
    
    if not embedding:
        raise HTTPException(status_code=500, detail="Failed to generate embedding")

    return {
        "object": "list",
        "data": [
            {
                "object": "embedding",
                "embedding": embedding,
                "index": 0
            }
        ],
        "model": request.model,
        "usage": {
            "prompt_tokens": 0,
            "total_tokens": 0
        }
    }


@app.post(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/config")
async def update_plugin_config(plugin_id: str, payload: PluginConfigUpdate):
    plugin = get_plugin(plugin_id)
    if not plugin:
        raise HTTPException(status_code=404, detail="Plugin not found")
    plugin.config.update(payload.config)
    try:
        await plugin.on_config_updated()
    except AttributeError:
        pass
    return {"status": "ok"}


@app.post(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/danmaku_batch")
async def summarize_danmaku_batch(plugin_id: str, payload: DanmakuBatchRequest):
    plugin = get_plugin(plugin_id)
    if not plugin or not isinstance(plugin, BilibiliLivePlugin):
        raise HTTPException(status_code=404, detail="Bilibili Live plugin not found")
    items = [item.model_dump() for item in payload.items]
    summary = await plugin.summarize_danmaku_batch(items or None)
    return {"summary": summary}


@app.post(f"{settings.API_V1_STR}/live/bilibili/event")
async def ingest_bilibili_event(payload: BilibiliEvent):
    plugin = get_plugin("bilibili_live")
    if not plugin or not isinstance(plugin, BilibiliLivePlugin):
        raise HTTPException(status_code=404, detail="Bilibili Live plugin not found")

    event = payload.model_dump()
    kind = event.get("kind") or "danmaku"
    user = event.get("user") or ""
    content = event.get("content") or ""
    price = event.get("price")

    if kind == "super_chat":
        await plugin.process_super_chat(content, user, price or 0.0)
    else:
        await plugin.process_danmaku(content, user)

    return {"status": "ok"}


@app.websocket(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/stream")
async def plugin_event_stream(websocket: WebSocket, plugin_id: str):
    await websocket.accept()
    plugin = get_plugin(plugin_id)
    if not plugin or not isinstance(plugin, BilibiliLivePlugin):
        await websocket.close(code=1008)
        return

    last_ts: Optional[float] = None

    try:
        while True:
            events = plugin.get_events_since(last_ts)
            if events:
                last_ts = float(events[-1].get("timestamp") or 0.0)
                payload = {"events": events}
                await websocket.send_text(json.dumps(payload, ensure_ascii=False))
            try:
                await asyncio.sleep(1.0)
            except asyncio.CancelledError:
                break
    except WebSocketDisconnect:
        return
    except Exception as e:
        logger.error(f"Bilibili plugin WebSocket stream error: {e}")
        try:
            await websocket.close(code=1011)
        except Exception:
            pass

@app.post("/v1/chat/completions", response_model=OpenAIResponse)
async def chat_completions(request: OpenAIRequest, raw_request: Request, background_tasks: BackgroundTasks):
    logger.info(f"Received chat completion request. Model: {request.model}")
    # Extract the last user message
    last_message_obj = next((m for m in reversed(request.messages) if m.role == "user"), None)
    
    if not last_message_obj:
        logger.warning("No user message found in request")
        raise HTTPException(status_code=400, detail="No user message found")

    # Handle multimodal content (extract text for logging/simple processing, but pass full content if needed)
    last_message_content = last_message_obj.content
    
    user_id = request.user or "default_user"
    
    # Extract Target LLM Config from Headers
    target_api_key = raw_request.headers.get("X-Target-Api-Key")
    target_base_url = raw_request.headers.get("X-Target-Base-Url")
    target_model = raw_request.headers.get("X-Target-Model")
    enable_search_str = raw_request.headers.get("X-Enable-Browser", "false")
    enable_search = enable_search_str.lower() == "true"
    search_region = raw_request.headers.get("X-Search-Region", "zh-CN")
    usage_type = raw_request.headers.get("X-Usage-Type", "main")
    persona_mode = raw_request.headers.get("X-Persona-Mode", "full")
    
    # Extract Temperature from Header (if provided by frontend logic) or Body
    # Frontend sends X-Temperature header now.
    header_temp = raw_request.headers.get("X-Temperature")
    temperature = float(header_temp) if header_temp else request.temperature
    
    # Extract Session ID
    session_id = raw_request.headers.get("X-Session-Id")

    # Extract Vision Agent Config
    vision_api_key = raw_request.headers.get("X-Vision-Api-Key")
    vision_base_url = raw_request.headers.get("X-Vision-Base-Url")
    vision_model = raw_request.headers.get("X-Vision-Model")
    vision_prompt = raw_request.headers.get("X-Vision-Prompt")
    if vision_prompt:
        vision_prompt = unquote(vision_prompt)
    vision_fallback_str = raw_request.headers.get("X-Vision-Fallback", "false")
    vision_fallback = vision_fallback_str.lower() == "true"
    
    # Extract TTS/Audio Config (support multiple header conventions)
    tts_api_key = (
        raw_request.headers.get("X-TTS-Api-Key")
        or raw_request.headers.get("X-SiliconFlow-Api-Key")
    )
    tts_base_url = (
        raw_request.headers.get("X-TTS-Base-Url")
        or raw_request.headers.get("X-SiliconFlow-Base-Url")
    )
    # Extract TTS Voice (New)
    tts_voice = (
        raw_request.headers.get("X-TTS-Voice")
        or raw_request.headers.get("X-SiliconFlow-Voice")
    )

    # Fallback: Authorization: Bearer <key>
    auth_header = raw_request.headers.get("Authorization")
    if not tts_api_key and auth_header and auth_header.startswith("Bearer "):
        tts_api_key = auth_header.replace("Bearer ", "").strip()
    # Fallback: use target LLM credentials if TTS not provided
    if not tts_api_key:
        tts_api_key = target_api_key
    if not tts_base_url:
        tts_base_url = target_base_url

    # Debug logging
    logger.info(f"X-Enable-Browser header: '{enable_search_str}' -> enable_search={enable_search}")
    logger.info(f"X-Search-Region: {search_region}")
    logger.info(f"Usage type: {usage_type}")
    if tts_api_key:
        logger.info("TTS API Key provided in headers")
    if vision_model:
        logger.info(f"Vision Agent Configured: {vision_model} (Fallback: {vision_fallback})")

    # Process via astra-me Logic
    try:
        # If usage_type is 'system' or 'memory', bypass the Persona/History/Mood logic
        # and just act as a raw LLM proxy. This prevents the backend from responding
        # as Firefly when the frontend just wants to extract memory or summarize text.
        if usage_type in ["system", "memory", "tool"]:
            logger.info(f"Processing system request (type={usage_type}), bypassing persona logic.")
            
            # Convert Pydantic messages to dicts
            raw_messages = [{"role": m.role, "content": m.content} for m in request.messages]
            
            response_text = await chat_service.llm.get_response(
                raw_messages,
                api_key=target_api_key,
                base_url=target_base_url,
                model=target_model,
                temperature=temperature
            )
            current_mood = None # No mood update for system tasks
        else:
            enable_backend_tts_header = raw_request.headers.get("X-Backend-TTS", "false")
            enable_backend_tts = enable_backend_tts_header.lower() in ["true", "1", "yes", "server"]
            response_text = await chat_service.process_message(
                last_message_content, 
                user_id,
                session_id=session_id,
                target_api_key=target_api_key,
                target_base_url=target_base_url,
                target_model=target_model,
                tts_api_key=tts_api_key,
                tts_base_url=tts_base_url,
                tts_voice=tts_voice,
                enable_search=enable_search,
                search_region=search_region,
                persona_mode=persona_mode,
                vision_config={
                    "api_key": vision_api_key,
                    "base_url": vision_base_url,
                    "model": vision_model,
                    "prompt": vision_prompt,
                    "fallback": vision_fallback
                },
                temperature=temperature,
                background_tasks=background_tasks,
                enable_backend_tts=enable_backend_tts
            )
            current_mood = chat_service.mood_service.get_current_mood(user_id)
        
        logger.info("Message processed successfully")

        return OpenAIResponse(
            choices=[
                OpenAIChoice(
                    index=0,
                    message=OpenAIMessage(role="assistant", content=response_text)
                )
            ],
            emotion=current_mood
        )
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/logs/backend")
async def get_backend_logs(raw_request: Request):
    max_header = raw_request.headers.get("X-Log-Max-Errors")
    if max_header:
        try:
            set_recent_error_max(int(max_header))
        except Exception:
            pass
    return {"errors": get_recent_errors()}

@app.post("/api/logs/frontend")
async def post_frontend_logs(payload: FrontendLogs):
    global _frontend_recent_errors
    if payload.max and payload.max > 0:
        max_n = int(payload.max)
    else:
        max_n = settings.LOG_MAX_ERRORS
    
    for item in payload.errors:
        # Store in memory for quick retrieval
        _frontend_recent_errors.append(item.model_dump())
        
        # Log to backend logger (file + console)
        log_msg = f"[Frontend Error] {item.message}"
        if item.exception:
            log_msg += f"\nException: {item.exception}"
        logger.error(log_msg)

    if len(_frontend_recent_errors) > max_n:
        _frontend_recent_errors = _frontend_recent_errors[-max_n:]
    return {"stored": len(payload.errors), "total": len(_frontend_recent_errors)}

@app.get("/api/logs/frontend")
async def get_frontend_logs():
    return {"errors": _frontend_recent_errors}

@app.get("/")
async def root():
    return {"message": f"Welcome to {settings.PROJECT_NAME} Backend (OpenAI Compatible)"}

@app.post("/v1/url/parse")
async def parse_url(request: Request):
    """
    Parse a single URL and return its content with images.
    Request body: {"url": "https://example.com"}
    """
    try:
        body = await request.json()
        url = body.get("url")
        
        if not url:
            raise HTTPException(status_code=400, detail="Missing 'url' field")
        
        if not url.startswith("http://") and not url.startswith("https://"):
            raise HTTPException(status_code=400, detail="Invalid URL format")
        
        logger.info(f"Parsing URL: {url}")
        
        page_content = await chat_service.search_service.visit_page(url)
        
        return {
            "url": url,
            "content": page_content
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error parsing URL: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


