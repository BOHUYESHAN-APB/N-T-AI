from typing import Dict, Any, Optional
import os
from openai import AsyncOpenAI

class CodeGenerator:
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    def _get_client(self) -> AsyncOpenAI:
        role_config = self.config.get("researcher") or {} # Share config with researcher for now
        api_key = role_config.get("api_key") or os.getenv("OPENAI_API_KEY")
        base_url = role_config.get("base_url") or os.getenv("OPENAI_BASE_URL")
        
        if not api_key:
            from app.core.config import settings
            api_key = settings.OPENAI_API_KEY
            base_url = settings.OPENAI_BASE_URL

        if not api_key:
             raise ValueError("No API Key provided for code generator")

        return AsyncOpenAI(api_key=api_key, base_url=base_url)

    def _get_model(self) -> str:
        role_config = self.config.get("researcher") or {}
        return role_config.get("model") or "gpt-3.5-turbo"

    async def generate_analysis_code(self, context: str, requirement: str, error_context: Optional[str] = None) -> str:
        """
        Generates Python code for data analysis/visualization.
        If error_context is provided, it attempts to fix the previous code.
        """
        client = self._get_client()
        model = self._get_model()

        system_prompt = """You are an expert Python Data Analyst.
Your task is to write Python code to analyze data and generate visualizations (matplotlib/seaborn).
The code will run in a sandboxed environment with:
- pandas, numpy, matplotlib, seaborn installed.
- Access to internet is RESTRICTED in this step. Use provided data.

RULES:
1. Output ONLY valid Python code. No markdown blocks (```python ... ```).
2. If creating charts, save them to the current working directory as 'chart_output.png'.
3. Print key insights using `print()`.
4. Handle data cleaning if text is messy.
5. Use Chinese for chart titles and labels if the input is Chinese.
6. Ensure matplotlib supports Chinese:
   `plt.rcParams['font.sans-serif'] = ['SimHei', 'Arial Unicode MS']`
"""
        
        user_prompt = f"""
Context (Data/Search Results):
{context[:5000]}... (truncated)

Requirement:
{requirement}

"""
        if error_context:
            user_prompt += f"\n\nPREVIOUS ERROR:\n{error_context}\n\nPlease fix the code."

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ]

        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=0.2 # Lower temperature for code
        )
        
        code = response.choices[0].message.content
        
        # Strip markdown if present
        if "```python" in code:
            code = code.split("```python")[1].split("```")[0].strip()
        elif "```" in code:
            code = code.split("```")[1].split("```")[0].strip()
            
        return code
