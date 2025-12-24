import openai
from app.core.config import settings

class LLMService:
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
            
            # Provider-specific fallbacks
            if not model:
                if base_url and 'siliconflow' in base_url:
                    target_model = 'BAAI/bge-m3'
                elif base_url and 'deepseek' in base_url:
                    # DeepSeek doesn't have an embedding model usually
                    pass

            try:
                response = await client.embeddings.create(
                    input=text,
                    model=target_model,
                    timeout=30.0 # 增加超时时间到 30s
                )
                return response.data[0].embedding
            except Exception as e:
                # Check for connection errors specifically
                err_msg = str(e).lower()
                is_connection_error = "connection" in err_msg or "timeout" in err_msg or "unreachable" in err_msg
                
                if not is_connection_error:
                    print(f"Embedding API error for model {target_model}: {e}")
                
                # 如果是 OpenAI 模型但失败了，或者明确知道不是 OpenAI 的 base_url，尝试使用通用模型
                # 对于非 OpenAI 渠道，text-embedding-ada-002 往往不可用，尝试回退到 BAAI/bge-m3
                is_openai = "openai.com" in (base_url or settings.OPENAI_BASE_URL or "")
                
                if (target_model == "text-embedding-ada-002" or not is_openai) and not is_connection_error:
                    try:
                        fallback_model = "BAAI/bge-m3"
                        # 如果是 siliconflow 以外的国产渠道，可能也有自己的模型名，这里先尝试通用的
                        print(f"Attempting fallback embedding with {fallback_model}...")
                        response = await client.embeddings.create(
                            input=text,
                            model=fallback_model,
                            timeout=30.0
                        )
                        return response.data[0].embedding
                    except Exception as fallback_err:
                        # print(f"Fallback embedding failed: {fallback_err}")
                        pass
                
                if is_connection_error:
                    # Log connection error more cleanly to avoid spam
                    # You could use a class-level variable to throttle this log
                    pass
                return []
                
        except Exception as e:
            # print(f"Embedding Service Error: {e}")
            return []
