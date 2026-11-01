from typing import Optional
from datetime import datetime
from sqlmodel import Field, SQLModel, create_engine

from app.core.config import settings
from sqlalchemy import inspect

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
    assistant_name: Optional[str] = None
    system_prompt: Optional[str] = None
    role: Optional[str] = Field(default="user")  # user/self_agent/system_doc
    know_times: int = Field(default=0)
    created_at: datetime = Field(default_factory=datetime.utcnow)

class MemoryPoint(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    person_id: int = Field(foreign_key="person.id")
    content: str
    category: str
    weight: float = Field(default=1.0)
    embedding: Optional[str] = None # JSON string of List[float]
    scope: Optional[str] = Field(default="long_term")  # long_term/scene/knowledge/mc_headful/mc_headless
    source: Optional[str] = None
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
engine = create_engine(settings.DATABASE_URL, echo=settings.SQL_ECHO)

def _migrate_sqlite_person_columns() -> None:
    if engine.url.get_backend_name() != "sqlite":
        return
    try:
        insp = inspect(engine)
        if "person" not in insp.get_table_names():
            return
        cols = {c["name"] for c in insp.get_columns("person")}
        stmts: list[str] = []
        if "assistant_name" not in cols:
            stmts.append("ALTER TABLE person ADD COLUMN assistant_name VARCHAR")
        if "system_prompt" not in cols:
            stmts.append("ALTER TABLE person ADD COLUMN system_prompt TEXT")
        if "role" not in cols:
            stmts.append("ALTER TABLE person ADD COLUMN role VARCHAR")
        if not stmts:
            return
        with engine.begin() as conn:
            for stmt in stmts:
                conn.exec_driver_sql(stmt)
    except Exception:
        return

def _migrate_sqlite_memorypoint_columns() -> None:
    if engine.url.get_backend_name() != "sqlite":
        return
    try:
        insp = inspect(engine)
        if "memorypoint" not in insp.get_table_names():
            return
        cols = {c["name"] for c in insp.get_columns("memorypoint")}
        stmts: list[str] = []
        if "scope" not in cols:
            stmts.append("ALTER TABLE memorypoint ADD COLUMN scope VARCHAR")
        if "source" not in cols:
            stmts.append("ALTER TABLE memorypoint ADD COLUMN source VARCHAR")
        if not stmts:
            return
        with engine.begin() as conn:
            for stmt in stmts:
                conn.exec_driver_sql(stmt)
    except Exception:
        return

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)
    _migrate_sqlite_person_columns()
    _migrate_sqlite_memorypoint_columns()
