from fastapi import APIRouter, HTTPException, Request, Body
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlmodel import Session, select
from app.models.database import engine, MemoryPoint, Person
from typing import List, Optional
from pydantic import BaseModel
import os

router = APIRouter()

# Setup templates
templates_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "templates")
if not os.path.exists(templates_dir):
    os.makedirs(templates_dir)
templates = Jinja2Templates(directory=templates_dir)

class MemoryCreate(BaseModel):
    user_id: str
    content: str
    category: str = "other"
    weight: float = 1.0

class MemoryUpdate(BaseModel):
    content: Optional[str] = None
    category: Optional[str] = None
    weight: Optional[float] = None

# Setup templates
templates_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "templates")
if not os.path.exists(templates_dir):
    os.makedirs(templates_dir)
templates = Jinja2Templates(directory=templates_dir)

@router.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@router.get("/v1/memory/all")
async def get_all_memories(limit: int = 20):
    """Endpoint for dashboard to fetch memories"""
    with Session(engine) as session:
        statement = select(MemoryPoint, Person.user_id).join(Person).order_by(MemoryPoint.created_at.desc()).limit(limit)
        results = session.exec(statement).all()
        
        memories = []
        for mp, user_id in results:
            memories.append({
                "id": mp.id,
                "user_id": user_id,
                "content": mp.content,
                "category": mp.category,
                "created_at": mp.created_at.isoformat(),
            })
        return memories

@router.get("/api/memories")
async def get_memories():
    with Session(engine) as session:
        # Join MemoryPoint with Person to get user_id
        statement = select(MemoryPoint, Person.user_id).join(Person)
        results = session.exec(statement).all()
        
        memories = []
        for mp, user_id in results:
            memories.append({
                "id": mp.id,
                "user_id": user_id,
                "content": mp.content,
                "category": mp.category,
                "created_at": mp.created_at.isoformat(),
                "weight": mp.weight
            })
        return memories

@router.delete("/api/memories/{memory_id}")
async def delete_memory(memory_id: int):
    with Session(engine) as session:
        memory = session.get(MemoryPoint, memory_id)
        if not memory:
            raise HTTPException(status_code=404, detail="Memory not found")
        session.delete(memory)
        session.commit()
        return {"ok": True}

@router.post("/api/memories/reset")
async def reset_memories():
    with Session(engine) as session:
        # Delete all memory points
        session.exec("DELETE FROM memorypoint")
        session.commit()
        return {"ok": True}

@router.post("/v1/memory")
async def create_memory(memory: MemoryCreate):
    """Create a new memory point"""
    with Session(engine) as session:
        # Find or create person
        person = session.exec(select(Person).where(Person.user_id == memory.user_id)).first()
        if not person:
            person = Person(user_id=memory.user_id)
            session.add(person)
            session.flush()
        
        # Create memory point
        mp = MemoryPoint(
            person_id=person.id,
            content=memory.content,
            category=memory.category,
            weight=memory.weight,
            embedding=[]  # Empty for now, can be populated later
        )
        session.add(mp)
        session.commit()
        session.refresh(mp)
        
        return {
            "id": mp.id,
            "user_id": memory.user_id,
            "content": mp.content,
            "category": mp.category,
            "weight": mp.weight,
            "created_at": mp.created_at.isoformat()
        }

@router.put("/v1/memory/{memory_id}")
async def update_memory(memory_id: int, memory: MemoryUpdate):
    """Update an existing memory point"""
    with Session(engine) as session:
        mp = session.get(MemoryPoint, memory_id)
        if not mp:
            raise HTTPException(status_code=404, detail="Memory not found")
        
        if memory.content is not None:
            mp.content = memory.content
        if memory.category is not None:
            mp.category = memory.category
        if memory.weight is not None:
            mp.weight = memory.weight
        
        session.add(mp)
        session.commit()
        session.refresh(mp)
        
        # Get user_id for response
        person = session.get(Person, mp.person_id)
        
        return {
            "id": mp.id,
            "user_id": person.user_id if person else "unknown",
            "content": mp.content,
            "category": mp.category,
            "weight": mp.weight,
            "created_at": mp.created_at.isoformat()
        }

@router.delete("/v1/memory/{memory_id}")
async def delete_memory_v1(memory_id: int):
    """Delete a memory point"""
    with Session(engine) as session:
        mp = session.get(MemoryPoint, memory_id)
        if not mp:
            raise HTTPException(status_code=404, detail="Memory not found")
        
        session.delete(mp)
        session.commit()
        return {"ok": True, "message": "Memory deleted successfully"}

