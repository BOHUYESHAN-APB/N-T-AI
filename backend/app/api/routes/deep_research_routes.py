from fastapi import APIRouter, HTTPException, BackgroundTasks, UploadFile, File, Form, Header
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import json
import asyncio
import uuid

from app.agents.deep_research import DeepResearchAgent
from app.services.file_service import file_ingestion_service
from app.services.vision_service import vision_service

router = APIRouter()

class DeepResearchRequest(BaseModel):
    query: str
    model_config_override: Optional[Dict[str, Any]] = None # API Key, Base URL etc.
    session_id: Optional[str] = None
    context_files: Optional[List[Dict[str, Any]]] = None
    depth: Optional[str] = "Medium"
    max_steps: Optional[int] = 5

class DeepResearchResponse(BaseModel):
    task_id: str
    status: str
    message: str
    data: Optional[Dict[str, Any]] = None

# In-memory store for active agents (for demo purposes)
# In production, use Redis or Database
active_agents: Dict[str, DeepResearchAgent] = {}

@router.delete("/task/{session_id}")
async def delete_research_task(session_id: str):
    """
    Deletes a research task session and its generated files.
    """
    import shutil
    import os
    
    # 1. Remove from active agents
    if session_id in active_agents:
        del active_agents[session_id]
        
    # 2. Delete generated files directory
    safe_session_id = "".join([c for c in session_id if c.isalnum() or c in ('-', '_')])
    report_dir = f"app/static/reports/{safe_session_id}"
    
    deleted_files = False
    if os.path.exists(report_dir):
        try:
            shutil.rmtree(report_dir)
            deleted_files = True
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to delete files: {str(e)}")
            
    return {"status": "success", "message": f"Session {session_id} deleted", "files_deleted": deleted_files}

@router.get("/task/{session_id}")
async def get_task_status(session_id: str):
    """
    Get the current status of a research task.
    Useful for polling if SSE connection is lost.
    """
    if session_id not in active_agents:
        raise HTTPException(status_code=404, detail="Task not found or expired")
    
    agent = active_agents[session_id]
    
    # Construct status response
    response = {
        "session_id": session_id,
        "status": "active", # If in active_agents, it's generally active or holding state
        "plan": [],
        "current_step": None,
        "logs": [] # We could expose recent logs if we stored them in a buffer
    }
    
    if agent.flow:
        snapshot = agent.flow.get_plan_snapshot()
        response["plan"] = snapshot
        
        # Find current step
        for step in snapshot:
            if step["status"] == "in_progress":
                response["current_step"] = step["title"]
                break
    
    return response

@router.post("/task/open_folder/{session_id}")
async def open_task_folder(session_id: str):
    """
    Opens the folder containing generated files for the given session.
    """
    import os
    import platform
    import subprocess
    
    safe_session_id = "".join([c for c in session_id if c.isalnum() or c in ('-', '_')])
    report_dir = os.path.abspath(f"app/static/reports/{safe_session_id}")
    
    if not os.path.exists(report_dir):
        # Fallback to base dir if specific dir doesn't exist yet
        report_dir = os.path.abspath("app/static/reports")
        
    try:
        if platform.system() == "Windows":
            os.startfile(report_dir)
        elif platform.system() == "Darwin":  # macOS
            subprocess.Popen(["open", report_dir])
        else:  # Linux
            subprocess.Popen(["xdg-open", report_dir])
        return {"status": "success", "message": "Folder opened"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to open folder: {str(e)}")

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
        session_id = request.session_id or f"dr_{uuid.uuid4().hex}"
        
        if session_id not in active_agents:
            active_agents[session_id] = DeepResearchAgent(model_config=agent_config, session_id=session_id)
            
        agent = active_agents[session_id]
        
        async def event_generator():
            try:
                yield f"data: {json.dumps({'type': 'metadata', 'session_id': session_id})}\n\n"
                async for event in agent.run_stream(request.query, context_files=request.context_files or [], depth=request.depth, max_steps=request.max_steps):
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
