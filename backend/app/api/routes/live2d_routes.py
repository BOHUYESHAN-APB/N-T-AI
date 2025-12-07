from fastapi import APIRouter, HTTPException, Request, Header
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from app.services.motion_agent_service import MotionAgentService
from app.services.llm_service import LLMService

router = APIRouter(prefix="/api/live2d", tags=["live2d"])

class MotionRequest(BaseModel):
    user_text: str
    ai_text: str
    emotion: str
    capabilities: Dict[str, List[str]] # {'motions': [], 'expressions': []}

class IdleRequest(BaseModel):
    emotion: str
    capabilities: Dict[str, List[str]]

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
