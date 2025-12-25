import openai
import time
from app.core.config import settings
from app.core.logger import logger

class LLMService:
    _last_emb_err_time = 0
    _emb_err_throttle = 60 # Seconds between error logs

    def __init__(self):
        # Default client using env vars
        self.default_client = openai.AsyncOpenAI(
            api_key=settings.OPENAI_API_KEY,
            base_url=settings.OPENAI_BASE_URL,
            timeout=60.0 # Explicit 60s timeout
        )

    async def get_response(self, messages: list, api_key: str = None, base_url: str = None, model: str = None, temperature: float = 0.7, timeout: float = 60.0, return_full: bool = False, enable_thinking: bool = False) -> str:
        try:
            # Determine client and config to use
            client = self.default_client
            target_model = model or settings.LLM_MODEL
            
            if api_key and base_url:
                client = openai.AsyncOpenAI(
                    api_key=api_key, 
                    base_url=base_url,
                    timeout=timeout
                )
            
            # Check for DeepSeek to enable thinking
            # deepseek-reasoner forces thinking (native), deepseek-chat needs explicit flag
            extra_body = {}
            if target_model and "deepseek" in target_model.lower():
                 if "reasoner" not in target_model.lower() and enable_thinking:
                     extra_body["thinking"] = {"type": "enabled"}
            
            response = await client.chat.completions.create(
                model=target_model,
                messages=messages,
                temperature=temperature,
                timeout=timeout,
                extra_body=extra_body if extra_body else None
            )
            
            message = response.choices[0].message
            content = message.content
            
            if return_full:
                return {
                    "content": content,
                    "reasoning_content": getattr(message, "reasoning_content", None),
                    "tool_calls": getattr(message, "tool_calls", None)
                }
            
            return content
        except Exception as e:
            print(f"LLM Error: {e}")
            # Re-raise exception so caller (ChatService) can handle fallbacks (e.g. downgrade to text-only)
            raise e

    async def get_response_stream(self, messages: list, api_key: str = None, base_url: str = None, model: str = None, temperature: float = 0.7, timeout: float = 60.0, enable_thinking: bool = False):
        try:
            client = self.default_client
            target_model = model or settings.LLM_MODEL
            
            if api_key and base_url:
                client = openai.AsyncOpenAI(
                    api_key=api_key, 
                    base_url=base_url,
                    timeout=timeout
                )
            
            extra_body = {}
            if target_model and "deepseek" in target_model.lower():
                 if "reasoner" not in target_model.lower() and enable_thinking:
                     extra_body["thinking"] = {"type": "enabled"}
            
            stream = await client.chat.completions.create(
                model=target_model,
                messages=messages,
                temperature=temperature,
                timeout=timeout,
                stream=True,
                extra_body=extra_body if extra_body else None
            )
            
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
                # Handle thinking/reasoning content if available
                if hasattr(chunk.choices[0].delta, "reasoning_content") and chunk.choices[0].delta.reasoning_content:
                    # We might want to handle this differently, but for now just yield as special marker or skip
                    # Yielding reasoning might be useful for thinking mode UI
                    pass

        except Exception as e:
            print(f"LLM Stream Error: {e}")
            raise e

    async def analyze_text(self, text: str, prompt: str, api_key: str = None, base_url: str = None, model: str = None, timeout: float = 60.0) -> str:
        """Generic method for analysis tasks (memory extraction, emotion, etc.)"""
        messages = [
            {"role": "system", "content": prompt},
            {"role": "user", "content": text}
        ]
        return await self.get_response(messages, api_key, base_url, model, timeout=timeout)

    async def get_embedding(self, text: str, api_key: str = None, base_url: str = None, model: str = None) -> list[float]:
        try:
            client = self.default_client
            if api_key and base_url:
                client = openai.AsyncOpenAI(api_key=api_key, base_url=base_url)

            # Use configured embedding model or fallback
            target_model = model or settings.LLM_EMBEDDING_MODEL
            
            # Provider-specific optimization: skip known chat-only models
            is_deepseek = base_url and 'deepseek' in base_url.lower()
            is_chat_only = is_deepseek and (not model or 'chat' in model.lower() or 'reasoner' in model.lower())
            
            if is_chat_only:
                # DeepSeek doesn't have an embedding model at its main endpoint.
                # Force fallback immediately to save 30s timeout.
                raise Exception("Detected chat-only model, skipping to fallback.")

            try:
                response = await client.embeddings.create(
                    input=text,
                    model=target_model,
                    timeout=10.0 # 缩短首次尝试超时时间
                )
                return response.data[0].embedding
            except Exception as e:
                # Check for connection errors specifically
                err_msg = str(e).lower()
                is_connection_error = "connection" in err_msg or "timeout" in err_msg or "unreachable" in err_msg
                
                now = time.time()
                should_log = (now - self._last_emb_err_time) > self._emb_err_throttle

                if not is_connection_error and should_log and not is_chat_only:
                    logger.warning(f"Embedding API error for model {target_model}: {e}")
                    self.__class__._last_emb_err_time = now
                
                # Fallback logic
                fallback_model = "BAAI/bge-m3"
                
                # Only fallback if it's not a connection error (which likely affects fallback too)
                # and if we are not already using the fallback model
                if not is_connection_error and target_model != fallback_model:
                    try:
                        if should_log:
                            logger.info(f"Attempting fallback embedding with {fallback_model}...")
                        
                        # Use siliconflow if the original was deepseek (often paired in this project)
                        # or if the current client is siliconflow
                        fallback_client = client
                        if is_deepseek:
                            # If the user is using deepseek, they probably don't have embeddings there.
                            # We might need a generic fallback client here if we want this to be robust.
                            pass

                        response = await client.embeddings.create(
                            input=text,
                            model=fallback_model,
                            timeout=10.0
                        )
                        return response.data[0].embedding
                    except Exception:
                        pass
                
                return [0.0] * 1536
                
        except Exception as e:
            return [0.0] * 1536
