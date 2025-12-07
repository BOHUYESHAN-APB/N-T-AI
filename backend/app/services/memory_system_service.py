import json
from sqlmodel import Session, select
from app.models.database import engine, ThinkingBack, MemoryPoint, Person
from app.services.llm_service import LLMService
from app.services.person_service import PersonService
from app.services.jargon_service import JargonService

class MemorySystemService:
    def __init__(self):
        self.llm = LLMService()
        self.person_service = PersonService()
        self.jargon_service = JargonService()

    async def retrieve_context(self, user_query: str, user_id: str, api_key: str = None, base_url: str = None, model: str = None) -> str:
        """
        Main entry point for ReAct memory retrieval.
        """
        context_results = []

        # 0. Vector Search (Lightweight RAG) - Always run
        vector_context = await self.retrieve_relevant_memories(user_query, user_id, api_key, base_url)
        if vector_context:
            context_results.append(vector_context)

        # 1. Thinking Back (Cache Check)
        cached_answer = self._check_thinking_back(user_query)
        if cached_answer:
            return f"Recalled from thought history: {cached_answer}"

        # 2. Question Generation
        plan = await self._generate_search_plan(user_query, api_key, base_url, model)
        
        # 3. Execute Tools
        if plan.get("search_person_info"):
            # Fallback to profile text if vector search missed something or for general stats
            profile = self.person_service.get_person_profile_text(user_id)
            if profile:
                context_results.append(f"User Profile Summary:\n{profile}")
        
        if plan.get("search_jargon"):
            jargon_context = self.jargon_service.get_jargon_context(user_query)
            if jargon_context:
                context_results.append(jargon_context)
                
        # (Add more tools like search_chat_history here)

        # 4. Save to Thinking Back (Simplified)
        if context_results:
            final_context = "\n".join(context_results)
            # self._save_thinking_back(user_query, final_context) # Optional: save the result
            return final_context
        
        return ""

    async def retrieve_relevant_memories(self, query: str, user_id: str, api_key: str = None, base_url: str = None, limit: int = 5) -> str:
        # 1. Get query embedding
        query_embedding = await self.llm.get_embedding(query, api_key, base_url)
        if not query_embedding:
            return ""

        # 2. Get all memories for user (Naive approach for small scale)
        with Session(engine) as session:
            # Join Person to filter by user_id
            statement = select(MemoryPoint).join(Person).where(Person.user_id == user_id)
            memories = session.exec(statement).all()

        if not memories:
            return ""

        # 3. Calculate Cosine Similarity
        scored_memories = []
        for mem in memories:
            if not mem.embedding:
                continue
            try:
                mem_emb = json.loads(mem.embedding)
                score = self._cosine_similarity(query_embedding, mem_emb)
                # Threshold to avoid irrelevant memories
                if score > 0.75:
                    scored_memories.append((score, mem.content))
            except:
                continue
        
        # 4. Sort and Top K
        scored_memories.sort(key=lambda x: x[0], reverse=True)
        top_k = scored_memories[:limit]
        
        if not top_k:
            return ""

        return "Relevant Memories (Vector Search):\n" + "\n".join([f"- {content}" for score, content in top_k])

    def _cosine_similarity(self, vec_a, vec_b):
        # Pure Python implementation
        if len(vec_a) != len(vec_b): return 0.0
        dot_product = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = sum(a * a for a in vec_a) ** 0.5
        norm_b = sum(b * b for b in vec_b) ** 0.5
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot_product / (norm_a * norm_b)

    def _check_thinking_back(self, query: str) -> str:
        # Simple hash check (in reality, semantic search is better)
        query_hash = str(hash(query))
        with Session(engine) as session:
            statement = select(ThinkingBack).where(ThinkingBack.question_hash == query_hash)
            result = session.exec(statement).first()
            return result.answer if result else None

    async def _generate_search_plan(self, query: str, api_key: str = None, base_url: str = None, model: str = None) -> dict:
        prompt = f"""
        Analyze the user query: "{query}"
        Determine what information is needed to answer.
        
        Available Tools:
        - search_person_info: If the query is about the user (preferences, name, history).
        - search_jargon: If the query contains slang or specific terms.
        
        Output JSON:
        {{
            "search_person_info": true/false,
            "search_jargon": true/false
        }}
        """
        response = await self.llm.get_response([{"role": "user", "content": prompt}], api_key, base_url, model)
        try:
            # Clean up JSON
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0]
            return json.loads(response)
        except:
            return {}
