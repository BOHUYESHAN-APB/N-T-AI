from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from openai import AsyncOpenAI
import os
import json

class TaskPlan(BaseModel):
    title: str = "Research Task"
    depth: str = "Medium"
    steps: List[str]
    max_steps: int = 5
    min_sources: int = 0
    current_step_index: int = 0

class Planner:
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    def _get_client(self) -> AsyncOpenAI:
        role_config = self.config.get("planner") or {}
        api_key = role_config.get("api_key") or os.getenv("OPENAI_API_KEY")
        base_url = role_config.get("base_url") or os.getenv("OPENAI_BASE_URL")
        
        if not api_key:
            # Fallback for compatibility
            from app.core.config import settings
            api_key = settings.OPENAI_API_KEY
            base_url = settings.OPENAI_BASE_URL

        if not api_key:
             raise ValueError("No API Key provided for planner role")

        return AsyncOpenAI(api_key=api_key, base_url=base_url)

    def _get_model(self) -> str:
        role_config = self.config.get("planner") or {}
        return role_config.get("model") or "gpt-3.5-turbo"

    async def generate_project_title(self, user_input: str) -> str:
        """Generates a short, concise title for the project."""
        try:
            client = self._get_client()
            model = self._get_model()
            sys_prompt = "You are a helpful assistant. Generate a short, concise title (max 15 chars) for the user's research request. No quotes, no markdown."
            response = await client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": f"Request: {user_input}"}
                ]
            )
            return response.choices[0].message.content.strip()
        except:
            return "New Project"

    async def analyze_request(self, user_input: str, memory_context: str, current_date: str, depth: str = "Medium", max_steps: int = 5) -> str:
        client = self._get_client()
        model = self._get_model()

        # Load prompts
        # Correctly locate prompts directory based on new structure
        # Current file: app/agents/deep_research/scripts/planner.py
        # Prompts: app/agents/deep_research/prompts/
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        prompts_dir = os.path.join(base_dir, "prompts")
        
        with open(os.path.join(prompts_dir, "planner.system.txt"), "r", encoding="utf-8") as f:
            sys_template = f.read()
        with open(os.path.join(prompts_dir, "planner.user.txt"), "r", encoding="utf-8") as f:
            user_template = f.read()

        sys_prompt = sys_template.replace("{{current_date}}", current_date)
        user_prompt = user_template.replace("{{user_input}}", user_input).replace("{{memory_context}}", memory_context)

        # Inject user preference
        user_prompt += f"\n\n[System Note]\nUser requested research depth: {depth}\nMax steps allowed: {max_steps}\nPlease generate a plan that respects these constraints."

        response = await client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={"type": "json_object"}
        )
        return response.choices[0].message.content
