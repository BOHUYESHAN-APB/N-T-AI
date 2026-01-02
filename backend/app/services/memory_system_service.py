import json
import math
import asyncio
import re
import time
from sqlmodel import Session, select
from sqlalchemy import or_
from app.core.config import settings
from app.models.database import engine, ThinkingBack, MemoryPoint, Person
from app.services.llm_service import LLMService
from app.services.person_service import PersonService
from app.services.jargon_service import JargonService

_LIGHT_PREFETCH_TTL_SEC = 120.0
_LIGHT_PREFETCH_MAX_USERS = 80
_LIGHT_PREFETCH_MAX_ENTRIES_PER_USER = 3
_light_prefetch_cache: dict[str, list[dict]] = {}

class MemorySystemService:
    def __init__(self):
        self.llm = LLMService()
        self.person_service = PersonService()
        self.jargon_service = JargonService()
        self._vector_backend = (getattr(settings, "VECTOR_MEMORY_BACKEND", "") or "sqlite").strip().lower()
        self._vector_http_url = (getattr(settings, "VECTOR_MEMORY_HTTP_URL", "") or "").strip()
        self._knowledge_backend = (getattr(settings, "KNOWLEDGE_BACKEND", "") or "").strip().lower()
        self._knowledge_http_url = (getattr(settings, "KNOWLEDGE_HTTP_URL", "") or "").strip()

    async def retrieve_context(
        self,
        user_query: str,
        user_id: str,
        api_key: str = None,
        base_url: str = None,
        model: str = None,
        embedding_api_key: str = None,
        embedding_base_url: str = None,
        embedding_model: str = None,
        scopes: list[str] | None = None,
        light_context: str | None = None,
        fast_mode: bool = False,
    ) -> str:
        """
        Main entry point for ReAct memory retrieval.
        """
        context_results = []

        previous_prefetch = self._consume_ready_light_prefetch(user_id=user_id)
        if previous_prefetch:
            context_results.append(previous_prefetch)

        if fast_mode:
            if light_context:
                context_results.append(light_context)
            return "\n".join([x for x in context_results if (x or "").strip()]).strip()

        # 0. Vector Search (Lightweight RAG) - Always run
        if light_context is None:
            light_context = await self._build_light_context(
                user_query=user_query,
                user_id=user_id,
                api_key=api_key,
                base_url=base_url,
                embedding_api_key=embedding_api_key,
                embedding_base_url=embedding_base_url,
                embedding_model=embedding_model,
                scopes=scopes,
            )
        if light_context:
            context_results.append(light_context)

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

        if plan.get("search_chat_history"):
            chat_context = await self.search_chat_history(user_query, user_id, limit=5)
            if chat_context:
                context_results.append(chat_context)
                
        # 4. Save to Thinking Back (Simplified)
        if context_results:
            final_context = "\n".join(context_results)
            # self._save_thinking_back(user_query, final_context) # Optional: save the result
            return final_context
        
        return ""

    async def search_chat_history(self, query: str, user_id: str, limit: int = 5) -> str:
        """
        Search recent chat history for keywords.
        """
        query = (query or "").strip()
        if not query:
            return ""

        keywords = self._extract_keywords(query)
        if not keywords:
            # If no keywords, return nothing or maybe last few messages? 
            # Better to return nothing to avoid noise if query is abstract.
            return ""

        from app.models.database import Conversation
        
        # Simple keyword match
        # Ideally, we should use vector search if available for chat history, 
        # but for now we stick to simple LIKE or fuzzy match.
        # Since SQLModel doesn't support complex full text search easily across DBs,
        # we'll fetch recent history and filter in python or use simple LIKE.
        
        with Session(engine) as session:
            # Fetch last 100 messages to search within reasonable window
            # Adjust limit as needed.
            statement = (
                select(Conversation)
                # .where(Conversation.session_id == user_id) # Assuming session_id can be user_id or we filter by it if available
                # Wait, Conversation table has session_id, but user_id is not directly there?
                # chat_service saves session_id. Let's assume session_id might match user_id or we ignore for now if not strictly linked.
                # Actually, chat_service.process_message uses session_id.
                # If user_id is passed as session_id or similar.
                # For now, let's search globally or assume session_id handling is consistent.
                # BUT, Conversation doesn't have user_id column in the model I saw.
                # It has session_id.
                .order_by(Conversation.id.desc())
                .limit(200) 
            )
            # If we want to filter by user/session, we need that info. 
            # chat_service passes user_id, but Conversation stores session_id.
            # Usually session_id IS user_id in many simple implementations, or distinct.
            # I'll try to filter by session_id if it matches user_id, otherwise search all (might be leaky).
            # To be safe, I will fetch all and if session_id matches user_id (if feasible).
            # Let's assume for this specific task context that session_id might be relevant.
            # Actually, looking at ChatService, it saves with session_id=session_id.
            # The user_id is passed to process_message.
            
            results = session.exec(statement).all()

        if not results:
            return ""

        hits = []
        for msg in results:
            content = (msg.content or "")
            if any(k in content for k in keywords):
                hits.append(f"[{msg.role}]: {content}")
                if len(hits) >= limit:
                    break
        
        if hits:
            return "Relevant Chat History (Keyword Match):\n" + "\n".join(hits)
        return ""

    async def retrieve_relevant_memories(
        self,
        query: str,
        user_id: str,
        api_key: str = None,
        base_url: str = None,
        embedding_api_key: str = None,
        embedding_base_url: str = None,
        embedding_model: str = None,
        scopes: list[str] | None = None,
        limit: int = 5,
    ) -> str:
        hits = await self.search_relevant_memories(
            query=query,
            user_id=user_id,
            api_key=api_key,
            base_url=base_url,
            embedding_api_key=embedding_api_key,
            embedding_base_url=embedding_base_url,
            embedding_model=embedding_model,
            scopes=scopes,
            limit=limit,
            threshold=0.72,
        )
        if not hits:
            return ""
        return "Relevant Memories (Vector Search):\n" + "\n".join([f"- {h['content']}" for h in hits])

    async def search_relevant_memories(
        self,
        query: str,
        user_id: str,
        api_key: str = None,
        base_url: str = None,
        embedding_api_key: str = None,
        embedding_base_url: str = None,
        embedding_model: str = None,
        scopes: list[str] | None = None,
        limit: int = 5,
        threshold: float = 0.72,
    ):
        query = (query or "").strip()
        user_id = (user_id or "").strip()
        if not query or not user_id:
            return []

        emb_key = embedding_api_key or api_key
        emb_base = embedding_base_url or base_url
        query_embedding = await self.llm.get_embedding(query, emb_key, emb_base, embedding_model)
        if not query_embedding:
            return []

        normalized_scopes = self._normalize_scopes(scopes)
        if self._vector_backend == "http" and self._vector_http_url and not normalized_scopes:
            hits = await self._search_relevant_memories_http(
                query_embedding=query_embedding,
                user_id=user_id,
                limit=limit,
                threshold=threshold,
            )
            if hits:
                return hits

        keywords = self._extract_keywords(query)
        now_ts = time.time()

        with Session(engine) as session:
            statement = (
                select(MemoryPoint, Person.user_id)
                .join(Person)
                .where(Person.user_id == user_id)
                .order_by(MemoryPoint.created_at.desc())
            )
            if normalized_scopes:
                if "long_term" in normalized_scopes:
                    statement = statement.where(
                        or_(
                            MemoryPoint.scope == None,  # noqa: E711
                            MemoryPoint.scope.in_(normalized_scopes),
                        )
                    )
                else:
                    statement = statement.where(MemoryPoint.scope.in_(normalized_scopes))
            results = session.exec(statement).all()

        if not results:
            return []

        filtered = results
        if len(results) > 600 and keywords:
            tmp = []
            for mp, uid in results:
                text = (mp.content or "")
                if any(k in text for k in keywords):
                    tmp.append((mp, uid))
                if len(tmp) >= 450:
                    break
            if tmp:
                filtered = tmp

        scored = []
        for mp, uid in filtered:
            if not mp.embedding:
                continue
            if normalized_scopes:
                scope = mp.scope or "long_term"
                if scope not in normalized_scopes:
                    continue
            try:
                mem_emb = json.loads(mp.embedding)
                cosine = self._cosine_similarity(query_embedding, mem_emb)
                if cosine <= 0:
                    continue
                age_days = 0.0
                try:
                    age_days = max(0.0, (now_ts - mp.created_at.timestamp()) / 86400.0)
                except Exception:
                    age_days = 0.0
                recency = math.exp(-age_days / 35.0)
                weight = float(getattr(mp, "weight", 1.0) or 1.0)
                weight_norm = min(max(weight / 3.0, 0.0), 1.0)
                score = (cosine * 0.88) + (recency * 0.07) + (weight_norm * 0.05)
                if score >= threshold:
                    scored.append(
                        (
                            score,
                            {
                                "id": mp.id,
                                "user_id": uid,
                                "content": mp.content,
                                "category": mp.category,
                                "weight": mp.weight,
                                "created_at": mp.created_at.isoformat(),
                                "score": score,
                            },
                        )
                    )
            except Exception:
                continue

        scored.sort(key=lambda x: x[0], reverse=True)
        top_k = [item for _, item in scored[: max(1, int(limit))]]
        return top_k

    def start_light_prefetch(
        self,
        *,
        user_query: str,
        user_id: str,
        api_key: str = None,
        base_url: str = None,
        embedding_api_key: str = None,
        embedding_base_url: str = None,
        embedding_model: str = None,
        scopes: list[str] | None = None,
    ):
        user_query = (user_query or "").strip()
        user_id = (user_id or "").strip()
        if not user_query or not user_id:
            return None

        now = time.time()
        self._cleanup_light_prefetch(now=now)

        existing_entries = _light_prefetch_cache.get(user_id)
        if isinstance(existing_entries, list):
            for entry in existing_entries:
                if not isinstance(entry, dict):
                    continue
                if (entry.get("query") or "") != user_query:
                    continue
                task = entry.get("task")
                if task and not task.done():
                    return task

        task = asyncio.create_task(
            self._build_light_context(
                user_query=user_query,
                user_id=user_id,
                api_key=api_key,
                base_url=base_url,
                embedding_api_key=embedding_api_key,
                embedding_base_url=embedding_base_url,
                embedding_model=embedding_model,
                scopes=scopes,
            )
        )

        new_entry = {
            "query": user_query,
            "task": task,
            "context": None,
            "created_at": now,
            "expires_at": now + _LIGHT_PREFETCH_TTL_SEC,
        }
        if not isinstance(existing_entries, list):
            existing_entries = []
        existing_entries.append(new_entry)
        _light_prefetch_cache[user_id] = existing_entries

        if len(existing_entries) > _LIGHT_PREFETCH_MAX_ENTRIES_PER_USER:
            existing_entries.sort(key=lambda e: float((e or {}).get("created_at") or 0.0))
            while len(existing_entries) > _LIGHT_PREFETCH_MAX_ENTRIES_PER_USER:
                drop = existing_entries.pop(0)
                drop_task = (drop or {}).get("task")
                if drop_task and not drop_task.done():
                    try:
                        drop_task.cancel()
                    except Exception:
                        pass

        def _on_done(t: asyncio.Task):
            entries = _light_prefetch_cache.get(user_id)
            if not isinstance(entries, list):
                return
            entry = None
            for e in entries:
                if isinstance(e, dict) and e.get("task") is t:
                    entry = e
                    break
            if entry is None:
                return
            try:
                res = t.result()
            except Exception:
                res = ""
            entry["context"] = (res or "").strip()

        try:
            task.add_done_callback(_on_done)
        except Exception:
            pass

        return task

    def _consume_ready_light_prefetch(self, *, user_id: str) -> str:
        user_id = (user_id or "").strip()
        if not user_id:
            return ""
        now = time.time()
        entries = _light_prefetch_cache.get(user_id)
        if not isinstance(entries, list) or not entries:
            return ""
        alive = []
        for e in entries:
            if not isinstance(e, dict):
                continue
            if float(e.get("expires_at") or 0.0) < now:
                continue
            alive.append(e)
        if not alive:
            _light_prefetch_cache.pop(user_id, None)
            return ""
        _light_prefetch_cache[user_id] = alive

        ready_entries = []
        for e in alive:
            task = e.get("task")
            if task and task.done():
                ready_entries.append(e)
        if not ready_entries:
            return ""
        ready_entries.sort(key=lambda e: float((e or {}).get("created_at") or 0.0))
        picked = ready_entries[-1]
        ctx = (picked.get("context") or "").strip()
        try:
            alive.remove(picked)
        except Exception:
            pass
        if alive:
            _light_prefetch_cache[user_id] = alive
        else:
            _light_prefetch_cache.pop(user_id, None)

        if not ctx:
            return ""
        return "Prefetched Context (Previous Turn):\n" + ctx

    def _cleanup_light_prefetch(self, *, now: float) -> None:
        if not _light_prefetch_cache:
            return
        for uid in list(_light_prefetch_cache.keys()):
            entries = _light_prefetch_cache.get(uid)
            if not isinstance(entries, list) or not entries:
                _light_prefetch_cache.pop(uid, None)
                continue
            alive = []
            for e in entries:
                if not isinstance(e, dict):
                    continue
                if float(e.get("expires_at") or 0.0) < now:
                    continue
                alive.append(e)
            if alive:
                _light_prefetch_cache[uid] = alive
            else:
                _light_prefetch_cache.pop(uid, None)
        if len(_light_prefetch_cache) <= _LIGHT_PREFETCH_MAX_USERS:
            return
        items = []
        for uid, e in _light_prefetch_cache.items():
            try:
                created = 0.0
                if isinstance(e, list) and e:
                    created = min(float((x or {}).get("created_at") or 0.0) for x in e if isinstance(x, dict))
                items.append((created, uid))
            except Exception:
                items.append((0.0, uid))
        items.sort(key=lambda x: x[0])
        for _, uid in items[: max(0, len(items) - _LIGHT_PREFETCH_MAX_USERS)]:
            _light_prefetch_cache.pop(uid, None)

    async def _build_light_context(
        self,
        *,
        user_query: str,
        user_id: str,
        api_key: str = None,
        base_url: str = None,
        embedding_api_key: str = None,
        embedding_base_url: str = None,
        embedding_model: str = None,
        scopes: list[str] | None = None,
    ) -> str:
        out = []
        vector_context = await self.retrieve_relevant_memories(
            user_query,
            user_id,
            api_key,
            base_url,
            embedding_api_key,
            embedding_base_url,
            embedding_model,
            scopes=scopes,
        )
        if vector_context:
            out.append(vector_context)
        external_context = await self.retrieve_external_knowledge(user_query=user_query, user_id=user_id)
        if external_context:
            out.append(external_context)
        return "\n".join([x for x in out if (x or "").strip()]).strip()

    def _normalize_scopes(self, scopes: list[str] | None) -> list[str]:
        if not scopes:
            return []
        normalized = []
        for scope in scopes:
            val = (scope or "").strip().lower()
            if val:
                normalized.append(val)
        return list(dict.fromkeys(normalized))

    async def retrieve_external_knowledge(self, user_query: str, user_id: str, limit: int = 4) -> str:
        if self._knowledge_backend == "http" and self._knowledge_http_url:
            items = await self._retrieve_external_knowledge_http(user_query=user_query, user_id=user_id, limit=limit)
            if items:
                out = []
                for it in items:
                    title = (it.get("title") or "").strip()
                    content = (it.get("content") or "").strip()
                    if title and content:
                        out.append(f"- {title}: {content}")
                    elif content:
                        out.append(f"- {content}")
                if out:
                    return "External Knowledge:\n" + "\n".join(out)
        return ""

    async def upsert_vector_index(
        self,
        *,
        user_id: str,
        memory_id: int,
        content: str,
        category: str,
        embedding: list,
        weight: float | None = None,
        created_at: str | None = None,
    ) -> None:
        if self._vector_backend != "http" or not self._vector_http_url:
            return
        await self._upsert_vector_http(
            user_id=user_id,
            memory_id=memory_id,
            content=content,
            category=category,
            embedding=embedding,
            weight=weight,
            created_at=created_at,
        )

    async def delete_vector_index(self, *, user_id: str, memory_id: int) -> None:
        if self._vector_backend != "http" or not self._vector_http_url:
            return
        await self._delete_vector_http(user_id=user_id, memory_id=memory_id)

    async def _search_relevant_memories_http(
        self,
        *,
        query_embedding: list,
        user_id: str,
        limit: int,
        threshold: float,
    ):
        try:
            import httpx

            async with httpx.AsyncClient(timeout=12.0) as client:
                resp = await client.post(
                    f"{self._vector_http_url.rstrip('/')}/search",
                    json={
                        "user_id": user_id,
                        "query_embedding": query_embedding,
                        "limit": int(limit),
                        "threshold": float(threshold),
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                items = data.get("items") if isinstance(data, dict) else None
                if not isinstance(items, list):
                    return []
                out = []
                for it in items:
                    if not isinstance(it, dict):
                        continue
                    content = (it.get("content") or "").strip()
                    if not content:
                        continue
                    out.append(
                        {
                            "id": it.get("id"),
                            "content": content,
                            "category": it.get("category") or "other",
                            "score": float(it.get("score") or 0.0),
                        }
                    )
                return out
        except Exception:
            return []

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
        try:
            import httpx

            payload = {
                "user_id": user_id,
                "id": memory_id,
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

    async def _delete_vector_http(self, *, user_id: str, memory_id: int) -> None:
        try:
            import httpx

            async with httpx.AsyncClient(timeout=12.0) as client:
                await client.post(
                    f"{self._vector_http_url.rstrip('/')}/delete",
                    json={"user_id": user_id, "id": int(memory_id)},
                )
        except Exception:
            return None

    async def _retrieve_external_knowledge_http(self, *, user_query: str, user_id: str, limit: int):
        try:
            import httpx

            async with httpx.AsyncClient(timeout=12.0) as client:
                resp = await client.post(
                    f"{self._knowledge_http_url.rstrip('/')}/query",
                    json={"user_id": user_id, "query": user_query, "limit": int(limit)},
                )
                resp.raise_for_status()
                data = resp.json()
                items = data.get("items") if isinstance(data, dict) else None
                if isinstance(items, list):
                    return [it for it in items if isinstance(it, dict)]
                return []
        except Exception:
            return []

    def _cosine_similarity(self, vec_a, vec_b):
        if not vec_a or not vec_b:
            return 0.0
        if len(vec_a) != len(vec_b):
            return 0.0
        dot_product = 0.0
        norm_a = 0.0
        norm_b = 0.0
        for a, b in zip(vec_a, vec_b):
            try:
                fa = float(a)
                fb = float(b)
            except Exception:
                return 0.0
            dot_product += fa * fb
            norm_a += fa * fa
            norm_b += fb * fb
        if norm_a <= 0.0 or norm_b <= 0.0:
            return 0.0
        return dot_product / ((norm_a ** 0.5) * (norm_b ** 0.5))

    def _extract_keywords(self, text: str):
        parts = re.findall(r"[\u4e00-\u9fffA-Za-z0-9_]{2,}", text or "")
        out = []
        seen = set()
        for p in parts:
            k = p.strip().lower()
            if not k or k in seen:
                continue
            seen.add(k)
            out.append(p.strip())
            if len(out) >= 8:
                break
        return out

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
        - search_chat_history: If the query refers to something said earlier in the conversation.
        
        Output JSON:
        {{
            "search_person_info": true/false,
            "search_jargon": true/false,
            "search_chat_history": true/false
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
