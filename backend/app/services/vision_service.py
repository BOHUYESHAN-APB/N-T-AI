"""
Vision Service
Wraps OpenAI/Claude Vision capabilities to describe images.
"""

import os
import base64
from typing import Optional
from openai import AsyncOpenAI

class VisionService:
    def __init__(self):
        # We can reuse the main provider config or env vars
        # Ideally this should be configurable per request, but for MVP we use env/default
        self.api_key = os.getenv("OPENAI_API_KEY")
        self.base_url = os.getenv("OPENAI_BASE_URL")
        self.model = "gpt-4o" # Default vision model

    def _encode_image(self, image_path: str) -> str:
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode('utf-8')

    async def describe_base64_image(self, base64_image: str, prompt: str = "Describe this image in detail for a research report.", api_key: str = None, base_url: str = None, model: str = None) -> str:
        """
        Generates a text description from a base64 encoded image string.
        """
        key = api_key or self.api_key
        url = base_url or self.base_url
        model_to_use = model or self.model
        
        if not key:
            return "[Vision Service: API Key not configured]"

        try:
            client = AsyncOpenAI(api_key=key, base_url=url)
            
            # Ensure base64 string doesn't have header if provided raw, or handle if it does
            # Usually API expects data:image/jpeg;base64,... but here we construct it.
            # If the user passes raw base64, we wrap it.
            
            image_url_content = f"data:image/jpeg;base64,{base64_image}"
            # Check if it already has data URI scheme
            if base64_image.startswith("data:image"):
                image_url_content = base64_image

            response = await client.chat.completions.create(
                model=model_to_use,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": image_url_content
                                },
                            },
                        ],
                    }
                ],
                max_tokens=300,
            )
            return response.choices[0].message.content
        except Exception as e:
            return f"[Vision Service Error: {str(e)}]"

    async def describe_image(self, image_path: str, prompt: str = "Describe this image in detail for a research report.", api_key: str = None, base_url: str = None, model: str = None) -> str:
        """
        Generates a text description of the image using a Vision LLM.
        """
        try:
            base64_image = self._encode_image(image_path)
            return await self.describe_base64_image(base64_image, prompt, api_key, base_url, model)
        except Exception as e:
            return f"[Vision Service Error: {str(e)}]"

vision_service = VisionService()
