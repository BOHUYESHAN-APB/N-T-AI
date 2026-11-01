from fastapi import FastAPI, HTTPException, Request, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse, FileResponse
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
from app.api.routes import memory_routes, model_routes, live2d_routes, audio_routes, deep_research_routes, linux_routes, minecraft_routes
from app.plugins import startup_plugins, shutdown_plugins, get_plugin
from app.plugins.bilibili_live import BilibiliLivePlugin
from app.services.sandbox_service import sandbox_service
from app.services.rag_service import temp_rag_service
from app.services.system_state import system_state

import logging

# Filter out /health endpoint logs from uvicorn.access
class EndpointFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        return record.args and len(record.args) >= 3 and record.args[2] != "/health"

# Apply the filter to uvicorn.access logger
logging.getLogger("uvicorn.access").addFilter(EndpointFilter())

from app.services.priority_manager import priority_manager

# Lifecycle manager
async def periodic_cleanup():
    """Background task to clean up old sessions."""
    while True:
        try:
            logger.info("[Cleanup] Running periodic cleanup for Sandbox and RAG sessions...")
            sandbox_service.cleanup_old_sessions(max_age_hours=24)
            temp_rag_service.cleanup_old_sessions(max_age_hours=24)
        except Exception as e:
            logger.error(f"[Cleanup] Error during periodic cleanup: {e}")
        await asyncio.sleep(3600) # Run every hour

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up Astra-Me Backend...")
    create_db_and_tables()
    await startup_plugins()
    # Start PriorityManager
    await priority_manager.start()
    
    # Start background cleanup task
    cleanup_task = asyncio.create_task(periodic_cleanup())
    
    try:
        yield
    finally:
        logger.info("Shutting down Astra-Me Backend...")
        cleanup_task.cancel()
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
# Mount audio routes at both /api/audio and /v1/audio for compatibility
app.include_router(audio_routes.router, prefix="/api/audio", tags=["audio"])
app.include_router(audio_routes.router, prefix="/v1/audio", tags=["audio_v1"])

# Deep Research Routes
app.include_router(deep_research_routes.router, prefix="/api/deep-research", tags=["deep_research"])

# Virtual Linux Environment Routes
app.include_router(linux_routes.router, prefix="/api/linux", tags=["linux"])

# Minecraft Plugin Routes
app.include_router(minecraft_routes.router, prefix=settings.API_V1_STR, tags=["minecraft"])

# Mount static files for Live2D/3D renderer
static_dir = os.path.join(os.path.dirname(__file__), "app", "static")
if not os.path.exists(static_dir):
    os.makedirs(static_dir)
app.mount("/static", StaticFiles(directory=static_dir), name="static")

@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    file_path = os.path.join(static_dir, "favicon.ico")
    if os.path.exists(file_path):
        return FileResponse(file_path)
    # Fallback to app_icon.png if favicon.ico doesn't exist yet
    png_path = os.path.join(static_dir, "app_icon.png")
    if os.path.exists(png_path):
        return FileResponse(png_path)
    return HTTPException(status_code=404)

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
    encoding_format: Optional[str] = None

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

_last_emb_err_time = 0
_emb_err_throttle = 60 # Seconds between error logs

@app.post("/v1/embeddings")
@app.post(f"{settings.API_V1_STR}/embeddings")
async def create_embeddings(request: EmbeddingRequest, raw_request: Request):
    global _last_emb_err_time
    target_api_key = raw_request.headers.get("X-Target-Api-Key")
    target_base_url = raw_request.headers.get("X-Target-Base-Url")
    target_model = raw_request.headers.get("X-Target-Model")
    if target_api_key in ("sk-ntai-internal", "sk-ntai-frontend"):
        target_api_key = None

    embedding_config = system_state.get_state("embedding_config") or {}
    if not target_api_key and embedding_config.get("api_key"):
        target_api_key = embedding_config.get("api_key")
    if not target_base_url and embedding_config.get("base_url"):
        target_base_url = embedding_config.get("base_url")
    if not target_model and embedding_config.get("model"):
        target_model = embedding_config.get("model")
    
    # Logic to apply inherited config
    if target_api_key == "sk-ntai-internal" or target_model == "main-brain":
        main_config = system_state.get_state("main_brain_config")
        if main_config:
            if not target_api_key or target_api_key == "sk-ntai-internal":
                target_api_key = main_config.get("api_key")
            
            # For embeddings, we usually want a specific embedding model
            # If the main brain model is a chat model (like deepseek), it won't work for embeddings
            main_model = main_config.get("model", "")
            if not target_model or target_model == "main-brain":
                # Check if it's a known chat-only model
                if "chat" in main_model.lower() or "instruct" in main_model.lower() or "deepseek" in main_model.lower():
                    # Use a default embedding model instead
                    target_model = embedding_config.get("model") or settings.LLM_EMBEDDING_MODEL
                    logger.info(f"Main brain model {main_model} is likely a chat model. Using default embedding model {target_model} instead.")
                else:
                    target_model = main_model

            # Only override base_url if it's pointing back to us or empty
            if not target_base_url or "127.0.0.1:23456" in target_base_url:
                target_base_url = main_config.get("base_url")
        else:
            # Fallback to backend's own env settings if no main_brain_config exists yet
            if not target_api_key or target_api_key == "sk-ntai-internal":
                target_api_key = settings.OPENAI_API_KEY
            if not target_base_url or "127.0.0.1:23456" in target_base_url:
                target_base_url = settings.OPENAI_BASE_URL
            if not target_model or target_model == "main-brain":
                target_model = embedding_config.get("model") or settings.LLM_EMBEDDING_MODEL
            logger.warning("No main_brain_config found for embedding, falling back to environment settings")

    # Fallback: Authorization: Bearer <key>
    auth_header = raw_request.headers.get("Authorization")
    if not target_api_key and auth_header and auth_header.startswith("Bearer "):
        target_api_key = auth_header.replace("Bearer ", "").strip()
        if target_api_key == "sk-ntai-internal":
            target_api_key = None # Use default key from env if it's the internal placeholder
    
    # Ensure target_api_key is None if it's still the internal placeholder
    if target_api_key == "sk-ntai-internal":
        target_api_key = None
    
    text_input = request.input
    if isinstance(text_input, list):
        text_input = text_input[0] 
        
    # Safety check: If we have no API key at this point (and not using a local no-auth provider), 
    # we should probably fail fast or return zero vector if it's critical.
    # However, some local backends might not require a key. 
    # But if we fell back to settings.OPENAI_API_KEY and it's empty, we are in trouble.
    
    embedding = None
    try:
        embedding = await chat_service.llm.get_embedding(text_input, api_key=target_api_key, base_url=target_base_url, model=target_model)
    except Exception as e:
        logger.error(f"Embedding generation error: {e}")
        # Will fall through to zero vector fallback
    
    if not embedding:
        # Fallback to a zero vector to avoid 500 error and keep the client running
        # Most models use 1536 (ada) or 1024 (bge). Using 1536 as a safe default for compatibility.
        now = time.time()
        if (now - _last_emb_err_time) > _emb_err_throttle:
            logger.warning(f"Embedding generation failed for input: {text_input[:50]}... Returning zero vector (Throttled).")
            _last_emb_err_time = now
        embedding = [0.0] * 1536

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


@app.get(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/status")
async def get_plugin_status(plugin_id: str):
    plugin = get_plugin(plugin_id)
    if not plugin:
        raise HTTPException(status_code=404, detail="Plugin not found")
    
    status = {
        "is_active": getattr(plugin, "is_active", True),
    }
    
    # 特殊处理 Minecraft 插件
    if (plugin_id == "minecraft" or plugin_id == "Minecraft-mindcraft") and hasattr(plugin, "logs"):
        status.update({
            "logs": plugin.logs,
            "ms_auth_code": getattr(plugin, "ms_auth_code", None),
            "ms_auth_url": getattr(plugin, "ms_auth_url", None),
            "control_mode": getattr(plugin, "control_mode", None),
            "headful_ready": getattr(plugin, "headful_ready", None),
            "headful_state": getattr(plugin, "_headful_last_state", None)
        })
    
    return status


@app.post(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/activate")
async def activate_plugin(plugin_id: str):
    plugin = get_plugin(plugin_id)
    if not plugin:
        raise HTTPException(status_code=404, detail="Plugin not found")
    
    success = await plugin.activate()
    if not success:
        raise HTTPException(status_code=500, detail="Failed to activate plugin")
    return {"status": "ok"}


@app.post(f"{settings.API_V1_STR}/plugins/{{plugin_id}}/deactivate")
async def deactivate_plugin(plugin_id: str):
    plugin = get_plugin(plugin_id)
    if not plugin:
        raise HTTPException(status_code=404, detail="Plugin not found")
    
    success = await plugin.deactivate()
    if not success:
        raise HTTPException(status_code=500, detail="Failed to deactivate plugin")
    return {"status": "ok"}


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
@app.post(f"{settings.API_V1_STR}/chat/completions", response_model=OpenAIResponse)
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
    embedding_api_key = raw_request.headers.get("X-Embedding-Api-Key")
    embedding_base_url = raw_request.headers.get("X-Embedding-Base-Url")
    embedding_model = raw_request.headers.get("X-Embedding-Model")
    if embedding_api_key in ("sk-ntai-internal", "sk-ntai-frontend"):
        embedding_api_key = None
    disable_memory_header = raw_request.headers.get("X-Disable-Memory", "false")
    disable_memory = disable_memory_header.lower() in ["true", "1", "yes"]

    if embedding_api_key or embedding_base_url or embedding_model:
        existing_embedding = system_state.get_state("embedding_config") or {}
        updated_embedding = dict(existing_embedding)
        if embedding_api_key:
            updated_embedding["api_key"] = embedding_api_key
        if embedding_base_url:
            updated_embedding["base_url"] = embedding_base_url
        if embedding_model:
            updated_embedding["model"] = embedding_model
        system_state.update_state("embedding_config", updated_embedding)
    
    # Logic to inherit "Main Brain" config
    usage_type = raw_request.headers.get("X-Usage-Type", "main")
    if target_api_key and target_api_key != "sk-ntai-internal":
        current_main = system_state.get_state("main_brain_config")
        # If usage is 'main', OR we don't have a main config yet, save this one
        if usage_type == "main" or not current_main:
            if not current_main or current_main.get("api_key") != target_api_key or current_main.get("base_url") != target_base_url:
                logger.info(f"Updating/Initializing main_brain_config from usage_type: {usage_type}")
                system_state.update_state("main_brain_config", {
                    "api_key": target_api_key,
                    "base_url": target_base_url,
                    "model": target_model
                })
    
    # Logic to apply inherited config
    if target_api_key == "sk-ntai-internal" or target_model == "main-brain":
        main_config = system_state.get_state("main_brain_config")
        if main_config:
            if not target_api_key or target_api_key == "sk-ntai-internal":
                target_api_key = main_config.get("api_key")
            if not target_model or target_model == "main-brain":
                target_model = main_config.get("model")
            # Only override base_url if it's pointing back to us or empty
            if not target_base_url or "127.0.0.1:23456" in target_base_url:
                target_base_url = main_config.get("base_url")
        else:
            # Fallback to backend's own env settings if no main_brain_config exists yet
            if not target_api_key or target_api_key == "sk-ntai-internal":
                target_api_key = settings.OPENAI_API_KEY
            if not target_base_url or "127.0.0.1:23456" in target_base_url:
                target_base_url = settings.OPENAI_BASE_URL
            if not target_model or target_model == "main-brain":
                target_model = settings.LLM_MODEL
            logger.warning("No main_brain_config found, falling back to environment settings")

    logger.info(f"Final target for {usage_type}: model={target_model}, base_url={target_base_url}")

    enable_search_str = raw_request.headers.get("X-Enable-Browser", "false")
    enable_search = enable_search_str.lower() == "true"
    enable_thinking_str = raw_request.headers.get("X-Enable-Thinking", "false")
    enable_thinking = enable_thinking_str.lower() in ["true", "1", "yes"]
    search_region = raw_request.headers.get("X-Search-Region", "zh-CN")
    usage_type = raw_request.headers.get("X-Usage-Type", "main")
    persona_mode = raw_request.headers.get("X-Persona-Mode", "full")
    chat_mode = raw_request.headers.get("X-Chat-Mode", "persona")
    deep_research_str = raw_request.headers.get("X-Deep-Research", "false")
    deep_research = deep_research_str.lower() in ["true", "1", "yes"]
    suppress_inner_monologue_str = raw_request.headers.get("X-Suppress-Inner-Monologue", "false")
    suppress_inner_monologue = suppress_inner_monologue_str.lower() in ["true", "1", "yes"]
    strict_no_markdown_str = raw_request.headers.get("X-Strict-No-Markdown", "false")
    strict_no_markdown = strict_no_markdown_str.lower() in ["true", "1", "yes"]
    system_state.update_state("chat_mode", chat_mode)
    system_state.update_state("persona_mode", persona_mode)
    system_state.update_state("suppress_inner_monologue", suppress_inner_monologue)
    system_state.update_state("strict_no_markdown", strict_no_markdown)
    user_nickname = raw_request.headers.get("X-User-Nickname")
    if user_nickname:
        try:
            user_nickname = unquote(user_nickname)
        except Exception:
            pass

    system_prompt_override = raw_request.headers.get("X-System-Prompt")
    if system_prompt_override:
        try:
            system_prompt_override = unquote(system_prompt_override)
        except Exception:
            pass

    assistant_name = raw_request.headers.get("X-Assistant-Name")
    if assistant_name:
        try:
            assistant_name = unquote(assistant_name)
        except Exception:
            pass

    learning_probability_header = raw_request.headers.get("X-Learning-Probability")
    try:
        learning_probability = float(learning_probability_header) if learning_probability_header else 1.0
    except Exception:
        learning_probability = 1.0
    
    # Extract Temperature from Header (if provided by frontend logic) or Body
    # Frontend sends X-Temperature header now.
    header_temp = raw_request.headers.get("X-Temperature")
    temperature = float(header_temp) if header_temp else request.temperature
    
    # Extract Session ID
    session_id = raw_request.headers.get("X-Session-Id")
    scene_context = raw_request.headers.get("X-Scene-Context")
    if scene_context:
        try:
            scene_context = unquote(scene_context)
        except Exception:
            pass
    scene_tasks = None
    scene_tasks_raw = raw_request.headers.get("X-Scene-Tasks")
    if scene_tasks_raw:
        try:
            decoded = unquote(scene_tasks_raw)
        except Exception:
            decoded = scene_tasks_raw
        try:
            parsed = json.loads(decoded)
            if isinstance(parsed, list):
                scene_tasks = [str(x) for x in parsed if str(x).strip()]
            elif isinstance(parsed, str):
                scene_tasks = [s.strip() for s in parsed.splitlines() if s.strip()]
        except Exception:
            scene_tasks = [s.strip() for s in decoded.splitlines() if s.strip()]
    scene_ttl_header = raw_request.headers.get("X-Scene-Ttl")
    try:
        scene_ttl_sec = float(scene_ttl_header) if scene_ttl_header else None
    except Exception:
        scene_ttl_sec = None

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

    # Extract Agent Configs
    agent_config = {
        "refiner": {
            "api_key": raw_request.headers.get("X-Refiner-Api-Key"),
            "base_url": raw_request.headers.get("X-Refiner-Base-Url"),
            "model": raw_request.headers.get("X-Refiner-Model"),
        },
        "tool_caller": {
            "api_key": raw_request.headers.get("X-ToolCaller-Api-Key"),
            "base_url": raw_request.headers.get("X-ToolCaller-Base-Url"),
            "model": raw_request.headers.get("X-ToolCaller-Model"),
        },
        "researcher": {
            "api_key": raw_request.headers.get("X-Researcher-Api-Key"),
            "base_url": raw_request.headers.get("X-Researcher-Base-Url"),
            "model": raw_request.headers.get("X-Researcher-Model"),
        }
    }

    # Debug logging
    logger.info(f"X-Enable-Browser header: '{enable_search_str}' -> enable_search={enable_search}")
    logger.info(f"X-Search-Region: {search_region}")
    if agent_config["refiner"]["model"]:
        logger.info(f"Agent Config (Refiner): {agent_config['refiner']['model']}")
    logger.info(f"Usage type: {usage_type}")
    if tts_api_key:
        logger.info("TTS API Key provided in headers")
    if vision_model:
        logger.info(f"Vision Agent Configured: {vision_model} (Fallback: {vision_fallback})")

    # Process proactive chat toggle
    enable_proactive_chat_header = raw_request.headers.get("X-Proactive-Chat", "false")
    enable_proactive_chat = enable_proactive_chat_header.lower() in ["true", "1", "yes"]
    priority_manager.set_proactive_chat(enable_proactive_chat)

    # Process via astra-me Logic
    try:
        # If usage_type is 'system' or 'memory', bypass the Persona/History/Mood logic
        # and just act as a raw LLM proxy. This prevents the backend from responding
        # as Firefly when the frontend just wants to extract memory or summarize text.
        if usage_type in ["system", "memory", "tool", "agent", "minecraft"]:
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
            enable_backend_tts_requested = enable_backend_tts_header.lower() in ["true", "1", "yes", "server"]
            enable_backend_tts = bool(settings.ALLOW_BACKEND_TTS) and enable_backend_tts_requested

            # 同步全局 TTS 开关状态，供插件使用（后端 TTS 默认禁用）
            system_state.update_state("enable_tts", enable_backend_tts)
            enable_vts_header = raw_request.headers.get("X-Enable-VTS", "false")
            enable_vts = enable_vts_header.lower() in ["true", "1", "yes"]
            system_state.update_state("enable_vts", enable_vts)
            
            if request.stream:
                async def stream_generator():
                    async for chunk in chat_service.process_message_stream(
                        last_message_content, 
                        user_id,
                        session_id=session_id,
                        target_api_key=target_api_key,
                        target_base_url=target_base_url,
                        target_model=target_model,
                        embedding_api_key=embedding_api_key,
                        embedding_base_url=embedding_base_url,
                        embedding_model=embedding_model,
                        scene_context=scene_context,
                        scene_tasks=scene_tasks,
                        scene_ttl_sec=scene_ttl_sec,
                        disable_memory=disable_memory,
                        tts_api_key=tts_api_key,
                        tts_base_url=tts_base_url,
                        tts_voice=tts_voice,
                        enable_search=enable_search,
                        enable_thinking=enable_thinking,
                        search_region=search_region,
                        persona_mode=persona_mode,
                        vision_config={
                            "api_key": vision_api_key,
                            "base_url": vision_base_url,
                            "model": vision_model,
                            "prompt": vision_prompt,
                            "fallback": vision_fallback
                        },
                        agent_config=agent_config,
                        temperature=temperature,
                        background_tasks=background_tasks,
                        enable_backend_tts=enable_backend_tts,
                        chat_mode=chat_mode,
                        deep_research=deep_research,
                        suppress_inner_monologue=suppress_inner_monologue,
                        strict_no_markdown=strict_no_markdown,
                        user_nickname=user_nickname,
                        system_prompt_override=system_prompt_override,
                        assistant_name=assistant_name,
                        learning_probability=learning_probability,
                        tts_mode=raw_request.headers.get("X-TTS-Mode", "sentence")
                    ):
                        yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"
                    yield "data: [DONE]\n\n"

                return StreamingResponse(stream_generator(), media_type="text/event-stream")

            response_text = await chat_service.process_message(
                last_message_content, 
                user_id,
                session_id=session_id,
                target_api_key=target_api_key,
                target_base_url=target_base_url,
                target_model=target_model,
                embedding_api_key=embedding_api_key,
                embedding_base_url=embedding_base_url,
                embedding_model=embedding_model,
                scene_context=scene_context,
                scene_tasks=scene_tasks,
                scene_ttl_sec=scene_ttl_sec,
                tts_api_key=tts_api_key,
                tts_base_url=tts_base_url,
                tts_voice=tts_voice,
                enable_search=enable_search,
                enable_thinking=enable_thinking,
                search_region=search_region,
                disable_memory=disable_memory,
                persona_mode=persona_mode,
                vision_config={
                    "api_key": vision_api_key,
                    "base_url": vision_base_url,
                    "model": vision_model,
                    "prompt": vision_prompt,
                    "fallback": vision_fallback
                },
                agent_config=agent_config,
                temperature=temperature,
                background_tasks=background_tasks,
                enable_backend_tts=enable_backend_tts,
                chat_mode=chat_mode,
                deep_research=deep_research,
                suppress_inner_monologue=suppress_inner_monologue,
                strict_no_markdown=strict_no_markdown,
                user_nickname=user_nickname,
                system_prompt_override=system_prompt_override,
                assistant_name=assistant_name,
                learning_probability=learning_probability,
                tts_mode=raw_request.headers.get("X-TTS-Mode", "sentence")
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

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "nt-ai-backend",
        "project": settings.PROJECT_NAME,
        "api_v1": settings.API_V1_STR,
        "features": {
            "deep_research": True,
            "live2d": True,
            "linux": True,
        },
    }

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
