from fastapi import APIRouter, HTTPException, BackgroundTasks, UploadFile, File, Form, Header
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import json
import asyncio

from app.agents.deep_research import DeepResearchAgent
from app.services.file_service import file_ingestion_service
from app.services.vision_service import vision_service

router = APIRouter()

class DeepResearchRequest(BaseModel):
    query: str
    model_config_override: Optional[Dict[str, Any]] = None # API Key, Base URL etc.
    session_id: Optional[str] = None
    context_files: Optional[List[Dict[str, Any]]] = None

class DeepResearchResponse(BaseModel):
    task_id: str
    status: str
    message: str
    data: Optional[Dict[str, Any]] = None

# In-memory store for active agents (for demo purposes)
# In production, use Redis or Database
active_agents: Dict[str, DeepResearchAgent] = {}

@router.post("/task")
async def create_research_task(request: DeepResearchRequest):
    """
    Starts a new Deep Research task. Returns a StreamingResponse (SSE).
    """
    try:
        # Initialize Agent
        # In a real app, we would load config from request or user settings
        agent_config = request.model_config_override or {} 
        
        # Use session_id or generate new
        session_id = request.session_id or f"session_{len(active_agents) + 1}"
        
        if session_id not in active_agents:
            active_agents[session_id] = DeepResearchAgent(model_config=agent_config)
            
        agent = active_agents[session_id]
        
        async def event_generator():
            try:
                yield f"data: {json.dumps({'type': 'metadata', 'session_id': session_id})}\n\n"
                async for event in agent.run_stream(request.query, context_files=request.context_files or []):
                    # SSE format: data: <json>\n\n
                    if isinstance(event, dict):
                        event = {**event, "session_id": session_id}
                    yield f"data: {json.dumps(event)}\n\n"
            except Exception as e:
                error_event = {"type": "error", "content": str(e), "session_id": session_id}
                yield f"data: {json.dumps(error_event)}\n\n"
            finally:
                # Close stream
                yield "event: close\ndata: [DONE]\n\n"

        return StreamingResponse(event_generator(), media_type="text/event-stream")
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...), 
    session_id: str = Form(...),
    x_target_api_key: Optional[str] = Header(None, alias="X-Target-Api-Key"),
    x_target_base_url: Optional[str] = Header(None, alias="X-Target-Base-Url")
):
    """
    Uploads a file to the research context.
    """
    try:
        # Save temp file
        file_path = f"uploads/{file.filename}"
        with open(file_path, "wb") as buffer:
            buffer.write(await file.read())
            
        # Parse content with Vision Callback
        async def vision_callback(image_path: str) -> str:
            # Pass header keys if available
            return await vision_service.describe_image(
                image_path, 
                api_key=x_target_api_key, 
                base_url=x_target_base_url
            )

        parsed_data = await file_ingestion_service.parse_file(file_path, vision_agent_callback=vision_callback)
        
        if "error" in parsed_data:
             raise HTTPException(status_code=400, detail=parsed_data["error"])
             
        # Add to agent memory if session exists
        if session_id in active_agents:
            agent = active_agents[session_id]
            agent.memory.append({
                "role": "system", 
                "content": f"File Content ({file.filename}):\n{parsed_data['content']}"
            })
            
        return {"filename": file.filename, "status": "processed"}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
