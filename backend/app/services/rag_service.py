"""
Temporary RAG Service
Provides a lightweight, session-based vector search for the Deep Research Agent.
Uses simple chunking and in-memory similarity search (simulated for now, can use Chroma/FAISS later).
"""

from typing import List, Dict, Any
import uuid

class TempRAGSession:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.documents: List[Dict[str, Any]] = [] # [{"content": "...", "metadata": {...}, "embedding": [...]}]
    
    def add_document(self, content: str, metadata: Dict[str, Any] = {}):
        """Chunks and stores document content."""
        # Simple chunking by paragraph or fixed size
        chunks = self._chunk_text(content)
        for chunk in chunks:
            self.documents.append({
                "id": str(uuid.uuid4()),
                "content": chunk,
                "metadata": metadata,
                # "embedding": ... # TODO: Add local embedding generation here
            })
            
    def search(self, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """
        Retrieves relevant chunks. 
        Currently implements a simple keyword match fallback until embeddings are added.
        """
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
                
        # Sort by score desc
        results.sort(key=lambda x: x["score"], reverse=True)
        return [r["doc"] for r in results[:top_k]]

    def _chunk_text(self, text: str, chunk_size: int = 500) -> List[str]:
        """Simple text chunker."""
        return [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]

class TempRAGService:
    def __init__(self):
        self._sessions: Dict[str, TempRAGSession] = {}

    def create_session(self) -> str:
        session_id = str(uuid.uuid4())
        self._sessions[session_id] = TempRAGSession(session_id)
        return session_id

    def get_session(self, session_id: str) -> TempRAGSession:
        return self._sessions.get(session_id)
        
    def delete_session(self, session_id: str):
        if session_id in self._sessions:
            del self._sessions[session_id]

temp_rag_service = TempRAGService()
