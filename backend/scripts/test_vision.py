import sys
import os

# Ensure we can import app
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

import asyncio
import base64
from app.services.vision_service import vision_service

# Small 1x1 red dot PNG base64
TEST_IMAGE_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

async def test_vision():
    print("Testing VisionService...")
    
    # Mocking or using real API key if available in env
    api_key = os.getenv("OPENAI_API_KEY") or os.getenv("SILICONFLOW_API_KEY")
    base_url = os.getenv("OPENAI_BASE_URL") or os.getenv("SILICONFLOW_BASE_URL")
    model = "gpt-4o"
    
    if os.getenv("SILICONFLOW_API_KEY") and not os.getenv("OPENAI_API_KEY"):
         # SiliconFlow usually uses Qwen for vision
         model = "Qwen/Qwen2-VL-7B-Instruct" # Example model
         if not base_url:
             base_url = "https://api.siliconflow.cn/v1"

    if not api_key:
        print("Warning: No API Key found in env. Skipping real API call.")
        return

    # Create a dummy image dict
    images = [
        {"name": "test_dot.png", "data": TEST_IMAGE_B64, "mime_type": "image/png"}
    ]
    
    try:
        # Use describe_base64_image directly
        print(f"Using model: {model}, base_url: {base_url}")
        description = await vision_service.describe_base64_image(
            TEST_IMAGE_B64, 
            api_key=api_key, 
            base_url=base_url,
            model=model
        )
        print("\n--- Vision Analysis Result ---")
        print(description)
        print("------------------------------")
        
        if "red" in description.lower() or "dot" in description.lower() or "pixel" in description.lower() or "image" in description.lower():
             print("SUCCESS: Vision service detected image content.")
        else:
             print("WARNING: Vision service returned description but might not be accurate.")
             
    except Exception as e:
        print(f"ERROR: Vision service failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_vision())
