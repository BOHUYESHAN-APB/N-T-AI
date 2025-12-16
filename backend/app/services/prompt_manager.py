"""
Prompt Manager
Handles loading and rendering of prompt templates.
"""

import os
from typing import Dict, Any
from pathlib import Path

class PromptManager:
    def __init__(self, prompt_dir: str = "app/prompts"):
        self.prompt_dir = Path(prompt_dir)

    def load_prompt(self, template_name: str) -> str:
        """
        Loads a prompt template from file.
        Args:
            template_name: Relative path to the prompt file (e.g. "deep_research/planner.txt")
        """
        try:
            path = self.prompt_dir / template_name
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            print(f"Error loading prompt {template_name}: {e}")
            return ""

    def render_prompt(self, template_name: str, context: Dict[str, Any]) -> str:
        """
        Loads and renders a prompt template with the given context.
        Uses simple {{key}} substitution.
        """
        template = self.load_prompt(template_name)
        if not template:
            return ""
            
        for key, value in context.items():
            template = template.replace(f"{{{{{key}}}}}", str(value))
            
        return template

prompt_manager = PromptManager()
