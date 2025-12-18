import datetime
import json
import os
from pathlib import Path
from typing import List, Dict, Any, Optional

from app.services.sandbox_service import sandbox_service
from .planner import Planner, TaskPlan
from .researcher import Researcher
from app.agents.deep_research.scripts.writer import Writer
from app.agents.deep_research.scripts.utils import normalize_user_input, detect_requested_formats, extract_file_content

class DeepResearchAgent:
    def __init__(self, model_config: Dict[str, Any]):
        self.config = model_config
        self.sandbox_session_id = sandbox_service.create_session()
        self.planner = Planner(model_config)
        self.researcher = Researcher(model_config)
        self.writer = Writer(model_config)
        self.memory: List[Dict[str, str]] = []

    def _get_sandbox_workspace_dir(self) -> Path:
        session = sandbox_service.get_session(self.sandbox_session_id)
        if session and getattr(session, "workspace_dir", None):
            return Path(session.workspace_dir)
        return Path("workspace") / self.sandbox_session_id

    def _append_research_log(self, content: str):
        try:
            log_path = self._get_sandbox_workspace_dir() / "research_log.md"
            os.makedirs(log_path.parent, exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(content + "\n\n")
        except Exception:
            pass

    def _read_research_log(self) -> str:
        try:
            log_path = self._get_sandbox_workspace_dir() / "research_log.md"
            if log_path.exists():
                return log_path.read_text(encoding="utf-8")
        except Exception:
            pass
        return ""

    async def run_stream(self, user_input: str, context_files: List[Dict] = []):
        """
        Main orchestration loop. Yields events.
        """
        current_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        user_input = normalize_user_input(user_input)
        
        # 0. Generate Title & Init Log
        project_title = await self.planner.generate_project_title(user_input)
        yield {
            "type": "metadata",
            "session_id": self.sandbox_session_id,
            "title": project_title
        }
        
        self._append_research_log(f"# Research Log: {project_title}\n\n**Date**: {current_date}\n**Request**: {user_input}\n\n---\n")

        # Context handling
        memory_context = ""
        if context_files:
             extracted_text = extract_file_content(context_files, self.writer.office_processor)
             if extracted_text:
                 self.memory.append({"role": "system", "content": f"Existing deliverable content (for revision):\n{extracted_text}"})

        self.memory.append({"role": "user", "content": user_input})

        # Build context string from memory history
        if len(self.memory) > 1:
            memory_context += "Previous Context/Conversation:\n"
            for msg in self.memory[:-1]: # Exclude current user input as it's passed separately
                 memory_context += f"- {msg['role']}: {msg['content']}\n"

        # 1. Planner Phase
        yield {"type": "step_start", "step": "Planning", "status": "Analyzing request..."}
        
        plan_response_json = await self.planner.analyze_request(user_input, memory_context, current_date)
        
        try:
            plan_data = json.loads(plan_response_json)
        except:
            # Fallback if JSON fails
            plan_data = {"steps": ["Research topic", "Summarize findings"]}

        if "clarification" in plan_data:
            yield {
                "type": "clarification", 
                "data": plan_data["clarification"]
            }
            return

        steps = plan_data.get("steps", [])
        yield {
            "type": "plan",
            "steps": steps
        }

        # 2. Research Phase
        for i, step in enumerate(steps):
            yield {
                "type": "step_start",
                "step": f"Researching: {step}",
                "current_step": i + 1,
                "total_steps": len(steps)
            }
            
            research_result = await self.researcher.execute_step(
                step, 
                user_input, 
                current_date, 
                depth=plan_data.get("depth", 3), 
                min_sources=plan_data.get("min_sources", 3)
            )
            self._append_research_log(f"## Step {i+1}: {step}\n\n{research_result}")
            
            yield {
                "type": "step_finish",
                "step": f"Completed: {step}",
                "data": research_result
            }

        # 3. Writer Phase
        yield {"type": "step_start", "step": "Writing", "status": "Generating documents..."}
        
        research_log = self._read_research_log()
        requested_formats = detect_requested_formats(user_input)
        
        generated_files = await self.writer.generate_document(user_input, research_log, requested_formats, current_date)
        
        yield {
            "type": "artifact",
            "files": generated_files
        }
        
        yield {"type": "done", "status": "success"}
