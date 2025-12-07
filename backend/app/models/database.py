from typing import Optional
from datetime import datetime
from sqlmodel import Field, SQLModel, create_engine

from app.core.config import settings

class Memory(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    content: str
    category: str  # preference, identity, experience, plan, other
    created_at: datetime = Field(default_factory=datetime.utcnow)
    importance: float = Field(default=1.0)

class Conversation(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: Optional[str] = Field(default=None, index=True)
    role: str
    content: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)

# --- New Models for astra-me Migration ---

class Person(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(index=True, unique=True)  # External ID
    nickname: Optional[str] = None
    know_times: int = Field(default=0)
    created_at: datetime = Field(default_factory=datetime.utcnow)

class MemoryPoint(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    person_id: int = Field(foreign_key="person.id")
    content: str
    category: str
    weight: float = Field(default=1.0)
    embedding: Optional[str] = None # JSON string of List[float]
    created_at: datetime = Field(default_factory=datetime.utcnow)

class Jargon(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    term: str = Field(index=True)
    definition: str
    context_example: Optional[str] = None
    frequency: int = Field(default=1)
    is_verified: bool = Field(default=False)

class ExpressionStyle(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    situation: str
    style: str
    example_context: Optional[str] = None

class ThinkingBack(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    question_hash: str = Field(index=True)
    question_text: str
    answer: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

class MoodState(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: str = Field(index=True, unique=True)
    current_mood: str
    last_updated: datetime = Field(default_factory=datetime.utcnow)

# Database Setup
engine = create_engine(settings.DATABASE_URL, echo=True)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)
