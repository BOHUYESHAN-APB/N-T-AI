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

            # Use a standard embedding model or configurable one
            # Many OpenAI-compatible APIs support text-embedding-ada-002 or similar
            # If the user didn't specify a model, try to guess based on the provider or use a safe default.
            # For SiliconFlow/DeepSeek, 'text-embedding-ada-002' might fail.
            # We'll try the requested model first, then fallback if it's the default.
            
            target_model = model or "text-embedding-ada-002"
            
            # Hack: If using SiliconFlow (often has 'siliconflow' in url), default to a known working model if not specified
            if base_url and 'siliconflow' in base_url and (not model or model == 'text-embedding-ada-002'):
                 target_model = 'BAAI/bge-m3' 

            try:
                response = await client.embeddings.create(
                    input=text,
                    model=target_model 
                )
                return response.data[0].embedding
            except openai.NotFoundError:
                # If 404, it means the model doesn't exist on this provider.
                # If we were using the default, try a common alternative or just return empty.
                if target_model == "text-embedding-ada-002":
                     print(f"Embedding model {target_model} not found. Returning empty embedding.")
                else:
                     print(f"Embedding model {target_model} not found.")
                return []
                
        except Exception as e:
            print(f"Embedding Error: {e}")
            return []
