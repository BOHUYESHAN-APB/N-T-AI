import json
from sqlmodel import Session, select
from app.models.database import engine, Person, MemoryPoint
from app.services.llm_service import LLMService
from datetime import datetime

class PersonService:
    def __init__(self):
        self.llm = LLMService()

    def get_or_create_person(self, user_id: str) -> Person:
        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                person = Person(user_id=user_id)
                session.add(person)
                session.commit()
                session.refresh(person)
            return person

    def increment_know_times(self, user_id: str):
        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if person:
                person.know_times += 1
                session.add(person)
                session.commit()

    async def add_memory_point(self, user_id: str, content: str, category: str, weight: float = 1.0):
        person = self.get_or_create_person(user_id)
        
        # Generate embedding
        embedding_list = await self.llm.get_embedding(content)
        embedding_json = json.dumps(embedding_list) if embedding_list else None

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
                    embedding=embedding_json
                )
                session.add(mp)
                session.commit()

    def get_person_profile_text(self, user_id: str) -> str:
        """Returns a text summary of the person for the LLM context."""
        with Session(engine) as session:
            statement = select(Person).where(Person.user_id == user_id)
            person = session.exec(statement).first()
            if not person:
                return ""
            
            mem_statement = select(MemoryPoint).where(MemoryPoint.person_id == person.id)
            memories = session.exec(mem_statement).all()
            
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
