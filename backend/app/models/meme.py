from sqlmodel import SQLModel, Field
from typing import List, Optional
from datetime import datetime
import json

class Meme(SQLModel, table=True):
    id: Optional[str] = Field(default=None, primary_key=True)
    path: str = Field(description="Relative path to the image file")
    description: str = Field(description="Visual description of the meme")
    embedding: str = Field(description="JSON string of embedding vector")
    created_at: datetime = Field(default_factory=datetime.now)
    usage_count: int = Field(default=0)
    
    @property
    def embedding_list(self) -> List[float]:
        if not self.embedding:
            return []
        try:
            return json.loads(self.embedding)
        except:
            return []
