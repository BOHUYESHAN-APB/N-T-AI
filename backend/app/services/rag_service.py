"""
Temporary RAG Service
Provides a lightweight, session-based vector search for the Deep Research Agent.
Uses simple chunking and in-memory similarity search (simulated for now, can use Chroma/FAISS later).
"""

from typing import List, Dict, Any
import uuid
import math
from datetime import datetime
from app.services.llm_service import LLMService

class TempRAGSession:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.documents: List[Dict[str, Any]] = [] # [{"content": "...", "metadata": {...}, "embedding": [...]}]
        self.llm = LLMService()
        self.created_at = datetime.now()
    
    async def add_document(self, content: str, metadata: Dict[str, Any] = {}):
        """Chunks and stores document content with embeddings."""
        # Simple chunking by paragraph or fixed size
        chunks = self._chunk_text(content)
        for chunk in chunks:
            embedding = await self.llm.get_embedding(chunk)
            self.documents.append({
                "id": str(uuid.uuid4()),
                "content": chunk,
                "metadata": metadata,
                "embedding": embedding
            })
            
    async def search(self, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """
        Retrieves relevant chunks using cosine similarity if embeddings are available.
        Falls back to keyword matching if no embeddings are found.
        """
        if not self.documents:
            return []

        # Check if we have embeddings for the first document
        has_embeddings = any(doc.get("embedding") for doc in self.documents)
        
        if has_embeddings:
            query_embedding = await self.llm.get_embedding(query)
            if not query_embedding:
                return self._keyword_search(query, top_k)
            
            results = []
            for doc in self.documents:
                doc_embedding = doc.get("embedding")
                if not doc_embedding:
                    continue
                
                score = self._cosine_similarity(query_embedding, doc_embedding)
                results.append({"doc": doc, "score": score})
            
            results.sort(key=lambda x: x["score"], reverse=True)
            return [r["doc"] for r in results[:top_k]]
        else:
            return self._keyword_search(query, top_k)

    def _keyword_search(self, query: str, top_k: int) -> List[Dict[str, Any]]:
        results = []
        query_terms = query.lower().split()
        
        for doc in self.documents:
            score = 0
            text = doc["content"].lower()
            for term in query_terms:
                if term in text:
                    score += 1
            
            if score > 0:
                results.append({"doc": doc, "score": score})
                
        results.sort(key=lambda x: x["score"], reverse=True)
        return [r["doc"] for r in results[:top_k]]

    def _cosine_similarity(self, v1: List[float], v2: List[float]) -> float:
        """Calculates cosine similarity between two vectors."""
        if not v1 or not v2 or len(v1) != len(v2):
            return 0.0
        
        dot_product = sum(a * b for a, b in zip(v1, v2))
        magnitude1 = math.sqrt(sum(a * a for a in v1))
        magnitude2 = math.sqrt(sum(a * a for a in v2))
        
        if magnitude1 == 0 or magnitude2 == 0:
            return 0.0
            
        return dot_product / (magnitude1 * magnitude2)

    def _chunk_text(self, text: str, chunk_size: int = 500) -> List[str]:
        """Simple text chunker."""
        if not text:
            return []
        # Try to split by paragraphs first to keep context together
        paragraphs = text.split('\n\n')
        chunks = []
        current_chunk = ""
        
        for p in paragraphs:
            if len(current_chunk) + len(p) < chunk_size:
                current_chunk += p + "\n\n"
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                # If a single paragraph is larger than chunk_size, split it by fixed size
                if len(p) > chunk_size:
                    for i in range(0, len(p), chunk_size):
                        chunks.append(p[i:i+chunk_size])
                    current_chunk = ""
                else:
                    current_chunk = p + "\n\n"
        
        if current_chunk:
            chunks.append(current_chunk.strip())
            
        return chunks

class TempRAGService:
    def __init__(self):
        self._sessions: Dict[str, TempRAGSession] = {}

    def create_session(self) -> str:
        session_id = str(uuid.uuid4())
        self._sessions[session_id] = TempRAGSession(session_id)
        return session_id

    def create_session_with_id(self, session_id: str) -> 'TempRAGSession':
        """Creates or retrieves a session with a specific ID."""
        if session_id not in self._sessions:
            self._sessions[session_id] = TempRAGSession(session_id)
        return self._sessions[session_id]

    def get_session(self, session_id: str) -> TempRAGSession:
        return self._sessions.get(session_id)
        
    def delete_session(self, session_id: str):
        if session_id in self._sessions:
            del self._sessions[session_id]

    def cleanup_old_sessions(self, max_age_hours: int = 24):
        """Deletes sessions older than max_age_hours."""
        now = datetime.now()
        to_delete = []
        for sid, session in self._sessions.items():
            age = now - session.created_at
            if age.total_seconds() > max_age_hours * 3600:
                to_delete.append(sid)
        
        for sid in to_delete:
            print(f"[RAG] Auto-cleaning expired session: {sid}")
            self.delete_session(sid)

temp_rag_service = TempRAGService()
