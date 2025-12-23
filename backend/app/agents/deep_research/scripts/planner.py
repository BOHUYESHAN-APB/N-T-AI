from typing import List, Dict, Any, Tuple
from pydantic import BaseModel
from openai import AsyncOpenAI
import os

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

    async def analyze_request(self, user_input: str, memory_context: str, current_date: str, depth: str = "Medium", max_steps: int = 5) -> Tuple[Dict[str, Any], Dict[str, Any]]:
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

        messages = [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": user_prompt}
        ]

        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            response_format={"type": "json_object"}
        )
        content = response.choices[0].message.content
        
        from .utils import extract_json_from_text
        import json
        
        plan_data = extract_json_from_text(content)
        if not plan_data:
            plan_data = {"steps": [], "title": "Research Plan"}

        debug_info = {
            "agent": "Planner",
            "model": model,
            "messages": messages,
            "response": content
        }

        if "clarification" in plan_data:
            return plan_data, debug_info

        # Clean up steps: remove "步骤 X:" or "Step X:" prefixes
        import re
        if "steps" in plan_data and isinstance(plan_data["steps"], list):
            cleaned_steps = []
            for step in plan_data["steps"]:
                # Remove nested "步骤 1:", "Step 1:", "1.", etc.
                cleaned = re.sub(r'^((步骤|Step|Step\s+)?\s*\d+[:.]\s*)+', '', step).strip()
                
                # Safeguard: If the LLM outputs a refusal message as a step, 
                # convert it to a clarification request.
                refusal_patterns = [
                    r"不支持.*(生成|提供|处理)", 
                    r"无法(提供|完成|生成).*(报告|综述|分析)",
                    r"抱歉.*(无法|不能).*(满足|提供)",
                    r"限制.*(生成|提供)"
                ]
                is_refusal = any(re.search(pattern, cleaned) for pattern in refusal_patterns)
                
                if is_refusal:
                    if "clarification" not in plan_data:
                        plan_data["clarification"] = {
                            "title": "需要更多信息",
                            "content": f"AI提示：{cleaned}。为了更好地完成任务，请补充以下信息：",
                            "questions": [
                                {
                                    "id": "refusal_fix",
                                    "type": "long_text",
                                    "label": "补充说明",
                                    "placeholder": "请具体说明您的研究目标、受众或所需格式..."
                                }
                            ]
                        }
                        return plan_data, debug_info
                
                cleaned_steps.append(cleaned)
            plan_data["steps"] = cleaned_steps

        return plan_data, debug_info
