from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlmodel import Session, select
from app.models.database import engine, MemoryPoint, Person, Jargon
from app.services.llm_service import LLMService
from app.services.memory_system_service import MemorySystemService
from typing import Optional, Dict, Any, List
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
    scope: str = "long_term"
    source: Optional[str] = None

class MemoryUpdate(BaseModel):
    content: Optional[str] = None
    category: Optional[str] = None
    weight: Optional[float] = None
    scope: Optional[str] = None
    source: Optional[str] = None

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
async def get_all_memories(
    limit: int = 20,
    user_id: Optional[str] = None,
    scope: Optional[str] = None,
):
    """Endpoint for dashboard to fetch memories"""
    with Session(engine) as session:
        statement = select(MemoryPoint, Person.user_id).join(Person)
        if user_id:
            statement = statement.where(Person.user_id == user_id)
        if scope:
            statement = statement.where(MemoryPoint.scope == scope)
        statement = statement.order_by(MemoryPoint.created_at.desc()).limit(limit)
        results = session.exec(statement).all()
        
        memories = []
        for mp, user_id in results:
            memories.append({
                "id": mp.id,
                "user_id": user_id,
                "content": mp.content,
                "category": mp.category,
                "scope": mp.scope or "long_term",
                "source": mp.source,
                "created_at": mp.created_at.isoformat(),
            })
        return memories

@router.get("/api/memories")
async def get_memories(
    user_id: Optional[str] = None,
    category: Optional[str] = None,
    scope: Optional[str] = None,
    q: Optional[str] = None,
    limit: int = 500,
):
    with Session(engine) as session:
        # Join MemoryPoint with Person to get user_id
        statement = select(MemoryPoint, Person.user_id).join(Person)
        if user_id:
            statement = statement.where(Person.user_id == user_id)
        if category:
            statement = statement.where(MemoryPoint.category == category)
        if scope:
            statement = statement.where(MemoryPoint.scope == scope)
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
                "scope": mp.scope or "long_term",
                "source": mp.source,
                "created_at": mp.created_at.isoformat(),
                "weight": mp.weight,
                "has_embedding": bool(mp.embedding),
            })
        return memories

@router.get("/api/v1/memory/retrieve")
async def retrieve_memory(
    query: str, 
    user_id: str, 
    api_key: Optional[str] = None, 
    base_url: Optional[str] = None,
    limit: int = 5
):
    """
    通用 RAG 检索接口，供插件或其他服务调用。
    """
    svc = MemorySystemService()
    context = await svc.retrieve_context(
        user_query=query,
        user_id=user_id,
        api_key=api_key,
        base_url=base_url,
        fast_mode=False
    )
    return {"context": context}

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
            scope=memory.scope or "long_term",
            source=memory.source,
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
        "scope": mp.scope or "long_term",
        "source": mp.source,
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
        if memory.scope is not None:
            mp.scope = memory.scope
        if memory.source is not None:
            mp.source = memory.source
        
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
        "scope": mp.scope or "long_term",
        "source": mp.source,
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

# --- Jargon CRUD ---

class JargonCreate(BaseModel):
    term: str
    definition: str
    context_example: Optional[str] = None
    is_verified: bool = True

class JargonUpdate(BaseModel):
    term: Optional[str] = None
    definition: Optional[str] = None
    context_example: Optional[str] = None
    is_verified: Optional[bool] = None

@router.get("/v1/jargon/all")
async def get_all_jargon(limit: int = 100):
    with Session(engine) as session:
        statement = select(Jargon).order_by(Jargon.term).limit(limit)
        results = session.exec(statement).all()
        return results

@router.post("/v1/jargon")
async def create_jargon(jargon: JargonCreate):
    with Session(engine) as session:
        db_jargon = Jargon(
            term=jargon.term,
            definition=jargon.definition,
            context_example=jargon.context_example,
            is_verified=jargon.is_verified
        )
        session.add(db_jargon)
        session.commit()
        session.refresh(db_jargon)
        return db_jargon

@router.put("/v1/jargon/{jargon_id}")
async def update_jargon(jargon_id: int, jargon: JargonUpdate):
    with Session(engine) as session:
        db_jargon = session.get(Jargon, jargon_id)
        if not db_jargon:
            raise HTTPException(status_code=404, detail="Jargon not found")
        
        if jargon.term is not None:
            db_jargon.term = jargon.term
        if jargon.definition is not None:
            db_jargon.definition = jargon.definition
        if jargon.context_example is not None:
            db_jargon.context_example = jargon.context_example
        if jargon.is_verified is not None:
            db_jargon.is_verified = jargon.is_verified
            
        session.add(db_jargon)
        session.commit()
        session.refresh(db_jargon)
        return db_jargon

@router.delete("/v1/jargon/{jargon_id}")
async def delete_jargon(jargon_id: int):
    with Session(engine) as session:
        db_jargon = session.get(Jargon, jargon_id)
        if not db_jargon:
            raise HTTPException(status_code=404, detail="Jargon not found")
        session.delete(db_jargon)
        session.commit()
        return {"ok": True}

# --- Person (User Info) CRUD ---

class PersonUpdate(BaseModel):
    nickname: Optional[str] = None
    assistant_name: Optional[str] = None
    system_prompt: Optional[str] = None
    role: Optional[str] = None

@router.get("/v1/person/all")
async def get_all_persons(limit: int = 50):
    with Session(engine) as session:
        statement = select(Person).order_by(Person.user_id).limit(limit)
        results = session.exec(statement).all()
        return results

@router.put("/v1/person/{user_id}")
async def update_person(user_id: str, person: PersonUpdate):
    with Session(engine) as session:
        db_person = session.exec(select(Person).where(Person.user_id == user_id)).first()
        if not db_person:
            # If person doesn't exist, create one
            db_person = Person(user_id=user_id)
            session.add(db_person)
            session.flush()
        
        if person.nickname is not None:
            db_person.nickname = person.nickname
        if person.assistant_name is not None:
            db_person.assistant_name = person.assistant_name
        if person.system_prompt is not None:
            db_person.system_prompt = person.system_prompt
        if person.role is not None:
            db_person.role = person.role
            
        session.add(db_person)
        session.commit()
        session.refresh(db_person)
        return db_person

@router.delete("/v1/person/{user_id}")
async def delete_person(user_id: str):
    with Session(engine) as session:
        db_person = session.exec(select(Person).where(Person.user_id == user_id)).first()
        if not db_person:
            raise HTTPException(status_code=404, detail="Person not found")
        session.delete(db_person)
        session.commit()
        return {"ok": True}
