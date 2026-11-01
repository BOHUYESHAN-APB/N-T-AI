import json
import threading
from sqlmodel import Session, select
from app.core.config import settings
from app.models.database import engine, Person, MemoryPoint
from app.services.llm_service import LLMService

class PersonService:
    def __init__(self):
        self.llm = LLMService()
        self._vector_backend = (getattr(settings, "VECTOR_MEMORY_BACKEND", "") or "sqlite").strip().lower()
        self._vector_http_url = (getattr(settings, "VECTOR_MEMORY_HTTP_URL", "") or "").strip()
        self._know_times_lock = threading.Lock()
        self._know_times_buffer: dict[str, int] = {}

    def get_or_create_person(self, user_id: str) -> Person:
        with Session(engine, expire_on_commit=False) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                person = Person(user_id=user_id, role="user")
                session.add(person)
                session.commit()
                session.refresh(person)
            elif not getattr(person, "role", None):
                person.role = "user"
                session.add(person)
                session.commit()
            return person

    def increment_know_times(self, user_id: str):
        try:
            batch_size = int(getattr(settings, "KNOW_TIMES_BATCH_SIZE", 10))
        except Exception:
            batch_size = 10
        if batch_size <= 0:
            return

        flush_delta = 0
        with self._know_times_lock:
            cur = self._know_times_buffer.get(user_id, 0) + 1
            if cur < batch_size:
                self._know_times_buffer[user_id] = cur
                return
            flush_delta = cur
            self._know_times_buffer.pop(user_id, None)

        if flush_delta <= 0:
            return

        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                person = Person(user_id=user_id, know_times=flush_delta)
                session.add(person)
            else:
                person.know_times += flush_delta
                session.add(person)
            session.commit()

    def upsert_persona(
        self,
        user_id: str,
        *,
        nickname: str | None = None,
        assistant_name: str | None = None,
        system_prompt: str | None = None,
    ) -> None:
        nickname = (nickname or "").strip() or None
        assistant_name = (assistant_name or "").strip() or None
        system_prompt = (system_prompt or "").strip() or None

        if nickname is None and assistant_name is None and system_prompt is None:
            return

        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                person = Person(user_id=user_id)
                session.add(person)
                session.commit()
                session.refresh(person)

            changed = False
            if nickname is not None and nickname != person.nickname:
                person.nickname = nickname
                changed = True
            if assistant_name is not None and getattr(person, "assistant_name", None) != assistant_name:
                setattr(person, "assistant_name", assistant_name)
                changed = True
            if system_prompt is not None and getattr(person, "system_prompt", None) != system_prompt:
                setattr(person, "system_prompt", system_prompt)
                changed = True

            if changed:
                session.add(person)
                session.commit()

    def upsert_role(self, user_id: str, role: str) -> None:
        role = (role or "").strip()
        if not role:
            return
        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                person = Person(user_id=user_id, role=role)
                session.add(person)
                session.commit()
                return
            if getattr(person, "role", None) != role:
                person.role = role
                session.add(person)
                session.commit()

    async def add_memory_point(
        self,
        user_id: str,
        content: str,
        category: str,
        weight: float = 1.0,
        scope: str = "long_term",
        source: str | None = None,
    ):
        person = self.get_or_create_person(user_id)
        
        # Generate embedding
        embedding_list = await self.llm.get_embedding(content)
        embedding_json = json.dumps(embedding_list) if embedding_list else None

        created_mp = None
        with Session(engine) as session:
            # Check for duplicates to avoid spamming memory
            statement = select(MemoryPoint).where(
                MemoryPoint.person_id == person.id,
                MemoryPoint.content == content
            )
            existing = session.exec(statement).first()
            if not existing:
                mp = MemoryPoint(
                    person_id=person.id,
                    content=content,
                    category=category,
                    weight=weight,
                    embedding=embedding_json,
                    scope=scope,
                    source=source,
                )
                session.add(mp)
                session.commit()
                session.refresh(mp)
                created_mp = mp

        if (
            self._vector_backend == "http"
            and self._vector_http_url
            and embedding_list
            and isinstance(embedding_list, list)
            and created_mp is not None
        ):
            await self._upsert_vector_http(
                user_id=user_id,
                memory_id=int(getattr(created_mp, "id", 0) or 0),
                content=content,
                category=category,
                embedding=embedding_list,
                weight=weight,
                created_at=getattr(created_mp, "created_at", None).isoformat()
                if getattr(created_mp, "created_at", None)
                else None,
            )

    async def _upsert_vector_http(
        self,
        *,
        user_id: str,
        memory_id: int,
        content: str,
        category: str,
        embedding: list,
        weight: float | None,
        created_at: str | None,
    ) -> None:
        if not memory_id:
            return
        try:
            import httpx

            payload = {
                "user_id": user_id,
                "id": int(memory_id),
                "content": content,
                "category": category,
                "embedding": embedding,
            }
            if weight is not None:
                payload["weight"] = float(weight)
            if created_at:
                payload["created_at"] = created_at
            async with httpx.AsyncClient(timeout=12.0) as client:
                await client.post(f"{self._vector_http_url.rstrip('/')}/upsert", json=payload)
        except Exception:
            return None

    def get_person_profile_text(self, user_id: str) -> str:
        """Returns a text summary of the person for the LLM context."""
        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                return ""
            
            # mem_statement = select(MemoryPoint).where(MemoryPoint.person_id == person.id)
            # memories = session.exec(mem_statement).all()
            
            profile = f"User ID: {person.user_id}\n"
            if person.nickname:
                profile += f"Nickname: {person.nickname}\n"
            profile += f"Interaction Count: {person.know_times}\n"
            
            # Only include memories if explicitly requested or for very short lists
            # For now, we disable full memory dump to prevent context pollution
            # if memories:
            #     profile += "Known Facts:\n"
            #     for mem in memories:
            #         profile += f"- [{mem.category}] {mem.content}\n"
            
            return profile
