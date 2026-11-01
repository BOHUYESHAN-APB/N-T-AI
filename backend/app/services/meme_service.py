import json
import math
import uuid
from typing import List
from datetime import datetime
from sqlmodel import Session, select
from app.models.database import engine
from app.models.meme import Meme
from app.services.llm_service import LLMService

class MemeService:
    def __init__(self):
        self.llm_service = LLMService()

    async def save_meme(self, path: str, description: str, api_key: str = None, base_url: str = None) -> Meme:
        """
        Save a new meme to the database with embedding.
        """
        embedding = await self.llm_service.get_embedding(description, api_key=api_key, base_url=base_url)
        
        meme = Meme(
            id=str(uuid.uuid4()),
            path=path,
            description=description,
            embedding=json.dumps(embedding),
            created_at=datetime.now(),
            usage_count=0
        )
        
        with Session(engine) as session:
            session.add(meme)
            session.commit()
            session.refresh(meme)
            
        return meme

    async def search_memes(self, query: str, limit: int = 1, threshold: float = 0.6, api_key: str = None, base_url: str = None) -> List[Meme]:
        """
        Search for relevant memes based on semantic similarity.
        """
        try:
            query_embedding = await self.llm_service.get_embedding(query, api_key=api_key, base_url=base_url)
            
            with Session(engine) as session:
                memes = session.exec(select(Meme)).all()
                
                scored_memes = []
                for meme in memes:
                    score = self._cosine_similarity(query_embedding, meme.embedding_list)
                    if score >= threshold:
                        scored_memes.append((meme, score))
                
                # Sort by score desc
                scored_memes.sort(key=lambda x: x[1], reverse=True)
                
                return [m[0] for m in scored_memes[:limit]]
        except Exception as e:
            print(f"[MemeService] Search error: {e}")
            return []

    def _cosine_similarity(self, vec_a: List[float], vec_b: List[float]) -> float:
        if not vec_a or not vec_b or len(vec_a) != len(vec_b):
            return 0.0
        
        dot_product = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))
        
        if norm_a == 0 or norm_b == 0:
            return 0.0
            
        return dot_product / (norm_a * norm_b)

    def increment_usage(self, meme_id: str):
        with Session(engine) as session:
            meme = session.get(Meme, meme_id)
            if meme:
                meme.usage_count += 1
                session.add(meme)
                session.commit()
