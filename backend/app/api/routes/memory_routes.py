from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlmodel import Session, select
from app.models.database import engine, MemoryPoint, Person
from app.services.llm_service import LLMService
from app.services.memory_system_service import MemorySystemService
from typing import Optional, Dict, Any
from pydantic import BaseModel
import os
import json

router = APIRouter()

# Setup templates
templates_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "templates")
os.makedirs(templates_dir, exist_ok=True)
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

class MemoryRebuildRequest(BaseModel):
    user_id: Optional[str] = None
    limit: int = 300
    force: bool = False

class MemorySearchResponse(BaseModel):
    items: list[Dict[str, Any]]

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
async def get_memories(user_id: Optional[str] = None, category: Optional[str] = None, q: Optional[str] = None, limit: int = 500):
    with Session(engine) as session:
        # Join MemoryPoint with Person to get user_id
        statement = select(MemoryPoint, Person.user_id).join(Person)
        if user_id:
            statement = statement.where(Person.user_id == user_id)
        if category:
            statement = statement.where(MemoryPoint.category == category)
        statement = statement.order_by(MemoryPoint.created_at.desc())
        results = session.exec(statement).all()

        qv = (q or "").strip()
        if qv:
            filtered = []
            for mp, uid in results:
                if qv in (mp.content or ""):
                    filtered.append((mp, uid))
                if len(filtered) >= max(1, int(limit)):
                    break
            results = filtered
        else:
            results = results[: max(1, int(limit))]
        
        memories = []
        for mp, user_id in results:
            memories.append({
                "id": mp.id,
                "user_id": user_id,
                "content": mp.content,
                "category": mp.category,
                "created_at": mp.created_at.isoformat(),
                "weight": mp.weight,
                "has_embedding": bool(mp.embedding),
            })
        return memories

@router.delete("/api/memories/{memory_id}")
async def delete_memory(memory_id: int):
    svc = MemorySystemService()
    with Session(engine) as session:
        statement = select(MemoryPoint, Person.user_id).join(Person).where(MemoryPoint.id == memory_id)
        row = session.exec(statement).first()
        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")
        mp, user_id = row
        session.delete(mp)
        session.commit()
    await svc.delete_vector_index(user_id=user_id, memory_id=int(memory_id))
    return {"ok": True}

@router.post("/api/memories/reset")
async def reset_memories():
    with Session(engine) as session:
        # Delete all memory points
        session.exec("DELETE FROM memorypoint")
        session.commit()
        return {"ok": True}

@router.get("/v1/memory/stats")
async def get_memory_stats():
    with Session(engine) as session:
        total_memories = session.exec(select(MemoryPoint)).all()
        total_users = session.exec(select(Person)).all()
        with_emb = 0
        categories: Dict[str, int] = {}
        latest = None
        for mp in total_memories:
            if mp.embedding:
                with_emb += 1
            categories[mp.category] = categories.get(mp.category, 0) + 1
            if latest is None or mp.created_at > latest:
                latest = mp.created_at
        return {
            "total_memories": len(total_memories),
            "total_users": len(total_users),
            "with_embeddings": with_emb,
            "without_embeddings": len(total_memories) - with_emb,
            "categories": categories,
            "latest_created_at": latest.isoformat() if latest else None,
        }

@router.get("/v1/memory/search", response_model=MemorySearchResponse)
async def search_memories(user_id: str, query: str, limit: int = 5, threshold: float = 0.72):
    svc = MemorySystemService()
    items = await svc.search_relevant_memories(
        query=query,
        user_id=user_id,
        limit=max(1, int(limit)),
        threshold=float(threshold),
    )
    return {"items": items}

@router.post("/v1/memory/rebuild_embeddings")
async def rebuild_embeddings(req: MemoryRebuildRequest):
    user_id = (req.user_id or "").strip()
    limit = max(1, int(req.limit))
    force = bool(req.force)

    llm = LLMService()
    svc = MemorySystemService()
    updated = 0
    scanned = 0
    to_upsert = []

    with Session(engine) as session:
        statement = select(MemoryPoint, Person.user_id).join(Person)
        if user_id:
            statement = statement.where(Person.user_id == user_id)
        statement = statement.order_by(MemoryPoint.created_at.desc())
        results = session.exec(statement).all()

        for mp, uid in results:
            scanned += 1
            if not force and mp.embedding:
                continue
            emb = await llm.get_embedding(mp.content)
            if emb:
                mp.embedding = json.dumps(emb, ensure_ascii=False)
                session.add(mp)
                updated += 1
                to_upsert.append((uid, mp.id, mp.content, mp.category, emb, mp.weight, mp.created_at.isoformat()))
            if updated >= limit:
                break
        session.commit()

    for uid, mid, content, category, emb, weight, created_at in to_upsert:
        await svc.upsert_vector_index(
            user_id=uid,
            memory_id=int(mid),
            content=content,
            category=category,
            embedding=emb,
            weight=weight,
            created_at=created_at,
        )
    return {"ok": True, "scanned": scanned, "updated": updated}

@router.post("/v1/memory")
async def create_memory(memory: MemoryCreate):
    """Create a new memory point"""
    llm = LLMService()
    emb = await llm.get_embedding(memory.content)
    embedding_json = json.dumps(emb, ensure_ascii=False) if emb else None
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
            embedding=embedding_json,
        )
        session.add(mp)
        session.commit()
        session.refresh(mp)
    if emb and isinstance(emb, list):
        svc = MemorySystemService()
        await svc.upsert_vector_index(
            user_id=memory.user_id,
            memory_id=int(mp.id),
            content=mp.content,
            category=mp.category,
            embedding=emb,
            weight=mp.weight,
            created_at=mp.created_at.isoformat(),
        )
    return {
        "id": mp.id,
        "user_id": memory.user_id,
        "content": mp.content,
        "category": mp.category,
        "weight": mp.weight,
        "created_at": mp.created_at.isoformat(),
    }

@router.put("/v1/memory/{memory_id}")
async def update_memory(memory_id: int, memory: MemoryUpdate):
    """Update an existing memory point"""
    llm = LLMService()
    svc = MemorySystemService()
    with Session(engine) as session:
        mp = session.get(MemoryPoint, memory_id)
        if not mp:
            raise HTTPException(status_code=404, detail="Memory not found")
        
        new_embedding_list = None
        if memory.content is not None:
            mp.content = memory.content
            new_embedding_list = await llm.get_embedding(memory.content)
            mp.embedding = json.dumps(new_embedding_list, ensure_ascii=False) if new_embedding_list else None
        if memory.category is not None:
            mp.category = memory.category
        if memory.weight is not None:
            mp.weight = memory.weight
        
        session.add(mp)
        session.commit()
        session.refresh(mp)
        
        # Get user_id for response
        person = session.get(Person, mp.person_id)

    embedding_for_upsert = new_embedding_list
    if embedding_for_upsert is None and mp.embedding:
        try:
            embedding_for_upsert = json.loads(mp.embedding)
        except Exception:
            embedding_for_upsert = None

    if embedding_for_upsert and isinstance(embedding_for_upsert, list) and person and person.user_id:
        await svc.upsert_vector_index(
            user_id=person.user_id,
            memory_id=int(mp.id),
            content=mp.content,
            category=mp.category,
            embedding=embedding_for_upsert,
            weight=mp.weight,
            created_at=mp.created_at.isoformat(),
        )

    return {
        "id": mp.id,
        "user_id": person.user_id if person else "unknown",
        "content": mp.content,
        "category": mp.category,
        "weight": mp.weight,
        "created_at": mp.created_at.isoformat(),
    }

@router.delete("/v1/memory/{memory_id}")
async def delete_memory_v1(memory_id: int):
    """Delete a memory point"""
    svc = MemorySystemService()
    with Session(engine) as session:
        statement = select(MemoryPoint, Person.user_id).join(Person).where(MemoryPoint.id == memory_id)
        row = session.exec(statement).first()
        if not row:
            raise HTTPException(status_code=404, detail="Memory not found")
        mp, user_id = row
        session.delete(mp)
        session.commit()
    await svc.delete_vector_index(user_id=user_id, memory_id=int(memory_id))
    return {"ok": True, "message": "Memory deleted successfully"}
