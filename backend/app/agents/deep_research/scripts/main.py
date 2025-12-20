import datetime
import json
import os
from pathlib import Path
from typing import List, Dict, Any, Optional

from app.services.sandbox_service import sandbox_service
from .planner import Planner, TaskPlan
from .researcher import Researcher
from app.agents.deep_research.scripts.writer import Writer
from app.agents.deep_research.scripts.utils import normalize_user_input, detect_requested_formats, extract_file_content, extract_json_from_text
from app.agents.deep_research.scripts.flow_manager import FlowManager, PlanStepStatus

class DeepResearchAgent:
    def __init__(self, model_config: Dict[str, Any], session_id: Optional[str] = None):
        self.config = model_config
        # Ensure session_id is provided or created, and is safe
        self.sandbox_session_id = session_id or sandbox_service.create_session()
        
        # Enforce strict workspace isolation (free-OKC style)
        # SandboxService now handles this automatically based on session_id
        
        self.planner = Planner(model_config)
        self.researcher = Researcher(model_config, session_id=self.sandbox_session_id)
        
        # Determine output directory relative to the isolated workspace
        # But for static serving, we still need to copy/link or use a known path.
        # However, to solve "History Leakage", we should prefer keeping files in the workspace
        # and only exposing them when needed.
        # For now, let's keep the app/static/reports pattern but ensure it's CLEANED or Unique.
        safe_session_id = "".join([c for c in self.sandbox_session_id if c.isalnum() or c in ('-', '_')])
        output_dir = f"app/static/reports/{safe_session_id}"
        os.makedirs(output_dir, exist_ok=True)
        
        self.writer = Writer(model_config, output_dir=output_dir)
        self.memory: List[Dict[str, str]] = []
        self.flow: Optional[FlowManager] = None

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

    async def run_stream(self, user_input: str, context_files: List[Dict] = [], depth: str = "Medium", max_steps: int = 5):
        """
        Main orchestration loop using FlowManager.
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
        
        self._append_research_log(f"# Research Log: {project_title}\n\n**Date**: {current_date}\n**Request**: {user_input}\n**Depth**: {depth}\n\n---\n")

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
        yield {"type": "step_start", "step": "任务分析", "status": "Analyzing request..."}
        
        plan_response_json, debug_info = await self.planner.analyze_request(user_input, memory_context, current_date, depth=depth, max_steps=max_steps)
        
        yield {
            "type": "log",
            "subtype": "llm_call",
            "content": debug_info
        }

        try:
            plan_data = extract_json_from_text(plan_response_json)
            if not plan_data:
                 raise ValueError("JSON parsing failed")
        except Exception as e:
            yield {
                "type": "log",
                "subtype": "error",
                "content": f"Planning failed: {str(e)}. Using default plan."
            }
            # Fallback if JSON fails
            plan_data = {"steps": ["Research topic", "Summarize findings"]}

        if "clarification" in plan_data:
            yield {
                "type": "clarification", 
                "title": plan_data["clarification"].get("title", "Clarification Needed"),
                "content": plan_data["clarification"].get("content", ""),
                "questions": plan_data["clarification"].get("questions", []),
                "auto_decide_seconds": plan_data["clarification"].get("auto_decide_seconds", 60)
            }
            return

        raw_steps = plan_data.get("steps", [])
        
        # Initialize Flow Manager
        self.flow = FlowManager(raw_steps)
        
        # Send initial plan to frontend
        yield {
            "type": "plan",
            "steps": [s.title for s in self.flow.steps]
        }

        # 2. Execution Phase (Managed by Flow)
        while True:
            step = self.flow.get_next_step()
            if not step:
                break
            
            # Start Step
            self.flow.mark_step_start(step.id)
            yield {
                "type": "step_start",
                "title": step.title,
                "desc": f"Executing {step.title}",
                "status": "in_progress"
            }
            
            try:
                research_result, debug_info = await self.researcher.execute_step(
                    step.title, 
                    user_input, 
                    current_date, 
                    depth=plan_data.get("depth", "Medium"), 
                    min_sources=plan_data.get("min_sources", 3)
                )
                
                yield {
                    "type": "log",
                    "subtype": "llm_call",
                    "content": debug_info
                }
                
                self._append_research_log(f"## Step: {step.title}\n\n{research_result}")
                
                # Mark Complete
                self.flow.mark_step_complete(step.id, result=research_result)
                yield {
                    "type": "step_finish",
                    "title": step.title,
                    "status": "completed"
                }
                
            except Exception as e:
                self.flow.mark_step_failed(step.id, error=str(e))
                yield {
                    "type": "step_finish",
                    "title": step.title,
                    "status": "failed",
                    "error": str(e)
                }
                # For now, we continue even if one step fails, or break?
                # Let's continue to try next steps.

        # 3. Writer Phase
        yield {"type": "step_start", "title": "Writing Report", "desc": "Generating final documents", "status": "in_progress"}
        
        research_log = self._read_research_log()
        requested_formats = detect_requested_formats(user_input)
        
        generated_files, debug_info = await self.writer.generate_document(user_input, research_log, requested_formats, current_date)
        
        yield {
            "type": "log",
            "subtype": "llm_call",
            "content": debug_info
        }
        
        yield {
            "type": "artifact",
            "files": generated_files
        }

        # Generate previews for HTML content
        for f in generated_files:
            if f.get("content") and isinstance(f["content"], str) and len(f["content"]) > 10:
                yield {
                    "type": "artifact_preview",
                    "data": {
                        "title": f.get("filename", "Preview"),
                        "html": f["content"],
                        "format": f.get("format", "unknown")
                    }
                }
        
        yield {"type": "final_result", "content": "All tasks completed successfully."}
        yield {"type": "done", "status": "success"}
