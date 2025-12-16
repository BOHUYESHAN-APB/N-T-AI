"""
Deep Research Agent
A hierarchical agent that plans tasks and uses specialized tools (Sandbox, Office Suite).
Inspired by OpenManus (ReAct + Planning) and DeepResearchAgent (Hierarchy).
"""

from typing import List, Dict, Any, Optional
from pydantic import BaseModel

from app.services.sandbox_service import sandbox_service
from app.tools.office_suite import PPTGenerator, WordGenerator, PDFGenerator
from app.tools.office_suite.excel_generator import excel_generator
from app.tools.web_search import web_search
from app.tools.academic_search import academic_search
from app.services.prompt_manager import prompt_manager

class TaskPlan(BaseModel):
    steps: List[str]
    current_step_index: int = 0

import os
from pathlib import Path
from openai import AsyncOpenAI
import json

class DeepResearchAgent:
    def __init__(self, model_config: Dict[str, Any]):
        """
        Args:
            model_config: Config for the LLM (API Key, Base URL, Model Name).
                          Structure: {"planner": {...}, "researcher": {...}, "writer": {...}}
        """
        self.config = model_config
        self.sandbox_session_id = sandbox_service.create_session()
        
        output_dir = "app/static/reports"
        self.ppt_generator = PPTGenerator(output_dir=output_dir)
        self.word_generator = WordGenerator(output_dir=output_dir)
        self.pdf_generator = PDFGenerator(output_dir=output_dir)
        
        # Memory specific to this agent instance
        self.memory: List[Dict[str, str]] = []
        self.plan: Optional[TaskPlan] = None

    def _get_client(self, role: str) -> AsyncOpenAI:
        """Creates an OpenAI client for the specific role."""
        role_config = self.config.get(role) or {}
        
        # Fallback to env vars if not provided
        api_key = role_config.get("api_key") or os.getenv("OPENAI_API_KEY")
        base_url = role_config.get("base_url") or os.getenv("OPENAI_BASE_URL")
        
        if not api_key:
            # Last resort for demo: raise error or use placeholder
            raise ValueError(f"No API Key provided for role: {role}")

        return AsyncOpenAI(api_key=api_key, base_url=base_url)

    def _get_model(self, role: str) -> str:
        role_config = self.config.get(role) or {}
        return role_config.get("model") or "gpt-3.5-turbo"

    async def _call_llm(self, role: str, messages: List[Dict[str, str]], stream: bool = False) -> str:
        client = self._get_client(role)
        model = self._get_model(role)
        
        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            stream=False # For internal logic we might not need stream
        )
        return response.choices[0].message.content

    async def run_stream(self, user_input: str, context_files: List[Dict] = []):
        """
        Stream version of run. Yields events.
        """
        # 1. Analysis Step (Real LLM Call)
        # Update memory with current user request
        self.memory.append({"role": "user", "content": user_input})
        
        # Build context from memory for Planner
        memory_context = ""
        if len(self.memory) > 1:
            memory_context = "Previous Conversation:\n"
            for msg in self.memory[:-1]:
                memory_context += f"- {msg['role']}: {msg['content']}\n"
        
        yield {
            "type": "step_start",
            "title": "Task Analysis",
            "desc": "Analyzing user request using Planner Agent...",
            "status": "running"
        }
        
        planner_system = prompt_manager.render_prompt("deep_research/planner.system.txt", {})
        planner_user = prompt_manager.render_prompt("deep_research/planner.user.txt", {
            "user_input": user_input,
            "memory_context": memory_context
        })
        
        try:
            plan_json = await self._call_llm("planner", [
                {"role": "system", "content": planner_system},
                {"role": "user", "content": planner_user}
            ])
            # Simple cleanup for JSON parsing
            if "```json" in plan_json:
                plan_json = plan_json.split("```json")[1].split("```")[0].strip()
            elif "```" in plan_json:
                plan_json = plan_json.split("```")[1].split("```")[0].strip()
                
            steps = json.loads(plan_json)
            
            yield {
                "type": "log",
                "step_title": "Task Analysis",
                "content": f"Plan generated: {', '.join(steps)}"
            }
        except Exception as e:
            yield {
                "type": "log",
                "step_title": "Task Analysis",
                "content": f"Planning failed, using default plan. Error: {str(e)}"
            }
            steps = ["Search Web", "Summarize Findings", "Generate Output"]

        yield {
             "type": "step_complete",
             "title": "Task Analysis",
             "status": "completed"
        }

        # 2. Execution Loop (Iterate through steps)
        # We will accumulate findings in a simple string buffer for the report
        research_findings = []
        
        for step in steps:
            yield {
                "type": "step_start",
                "title": step,
                "desc": "Executing research step...",
                "status": "running"
            }
            
            # Ask Researcher Model what to do: Search or Just Analyze?
            researcher_system = prompt_manager.render_prompt("deep_research/researcher.system.txt", {})
            researcher_user = prompt_manager.render_prompt("deep_research/researcher.user.txt", {
                "step": step
            })
            
            try:
                action_response = await self._call_llm("researcher", [
                    {"role": "system", "content": researcher_system},
                    {"role": "user", "content": researcher_user}
                ])
                
                # Parse action
                action_data = {}
                try:
                    clean_json = action_response
                    if "```json" in clean_json:
                        clean_json = clean_json.split("```json")[1].split("```")[0].strip()
                    elif "```" in clean_json:
                        clean_json = clean_json.split("```")[1].split("```")[0].strip()
                    action_data = json.loads(clean_json)
                except:
                    # Fallback if LLM didn't output valid JSON
                    action_data = {"action": "analyze", "thought": action_response}

                step_content = ""
                action_type = action_data.get("action")
                
                if action_type in ["search", "academic_search"]:
                    query = action_data.get("query", step)
                    tool_name = "Web" if action_type == "search" else "Academic (ArXiv)"
                    yield {
                        "type": "log", 
                        "step_title": step,
                        "content": f"Searching {tool_name} for: {query}"
                    }
                    
                    # Perform Real Search
                    if action_type == "academic_search":
                        search_results = academic_search.search(query, max_results=3)
                    else:
                        search_results = web_search.search(query, max_results=3)
                    
                    # Summarize results
                    snippets = []
                    for r in search_results:
                        if 'error' in r:
                            continue
                        source_info = f"Source: {r.get('href')}"
                        snippets.append(f"- {r['title']} ({source_info}): {r.get('body', '')[:300]}...")
                    
                    if not snippets:
                        snippets = ["No relevant results found."]
                        
                    step_content = f"Search Results for '{query}' ({tool_name}):\n" + "\n".join(snippets)
                    yield {
                        "type": "log",
                        "step_title": step,
                        "content": f"Found {len(search_results)} results."
                    }
                    
                else:
                    thought = action_data.get("thought", "Analyzing data...")
                    yield {
                        "type": "log", 
                        "step_title": step,
                        "content": thought
                    }
                    step_content = f"Analysis: {thought}"

                # Store findings
                research_findings.append(f"## Step: {step}\n{step_content}\n")

            except Exception as e:
                yield {
                    "type": "log", 
                    "step_title": step,
                    "content": f"Error executing step: {str(e)}"
                }
                
            yield {
                 "type": "step_complete",
                 "title": step,
                 "status": "completed"
            }

        # 3. Final Artifact Generation (Writer Agent)
        yield {
            "type": "step_start",
            "title": "Report Generation",
            "desc": "Compiling final report...",
            "status": "running"
        }
        
        # Generate Report Content using Writer LLM
        all_findings_text = "\n".join(research_findings)
        writer_system = prompt_manager.render_prompt("deep_research/writer.system.txt", {})
        writer_user = prompt_manager.render_prompt("deep_research/writer.user.txt", {
            "user_input": user_input,
            "research_findings": all_findings_text
        })
        
        try:
            writer_response = await self._call_llm("writer", [
                {"role": "system", "content": writer_system},
                {"role": "user", "content": writer_user}
            ])
            
            # Cleanup JSON
            try:
                clean_json = writer_response
                if "```json" in clean_json:
                    clean_json = clean_json.split("```json")[1].split("```")[0].strip()
                elif "```" in clean_json:
                    clean_json = clean_json.split("```")[1].split("```")[0].strip()
                output_data = json.loads(clean_json)
            except:
                # Fallback to docx if JSON parse fails
                output_data = {
                    "format": "docx",
                    "content": writer_response,
                    "filename": f"Report_{user_input[:10]}.docx"
                }
            
            output_format = output_data.get("format", "docx")
            content = output_data.get("content")
            filename = output_data.get("filename", "report")
            
            output_dir = "app/static/reports" # Fixed path relative to backend root
            os.makedirs(output_dir, exist_ok=True)
            
            artifact_path = ""
            artifact_type = "DOCX"
            
            if output_format == "excel" and isinstance(content, list):
                artifact_type = "XLSX"
                if not filename.endswith(".xlsx"): filename += ".xlsx"
                excel_generator.output_dir = output_dir
                artifact_path = excel_generator.generate_excel(content, filename)
                
            elif output_format == "ppt" and isinstance(content, list):
                artifact_type = "PPTX"
                if not filename.endswith(".pptx"): filename += ".pptx"
                
                # Convert JSON slides to HTML structure for PPTGenerator
                ppt_html = ""
                for slide in content:
                    ppt_html += f"<div class='ppt-slide'><h1>{slide.get('title', 'Slide')}</h1>"
                    if isinstance(slide.get('content'), list):
                        ppt_html += "<ul>" + "".join([f"<li>{item}</li>" for item in slide['content']]) + "</ul>"
                    else:
                        ppt_html += f"<p>{slide.get('content', '')}</p>"
                    ppt_html += "</div>"
                
                artifact_path = self.ppt_generator.generate_ppt(ppt_html, filename)

            elif output_format == "pdf":
                artifact_type = "PDF"
                if not filename.endswith(".pdf"): filename += ".pdf"
                
                # Convert content to string/HTML if needed
                if not isinstance(content, str): 
                     # If content is structured (e.g. from writer JSON), convert to simple HTML
                     if isinstance(content, list):
                         html_body = ""
                         for section in content:
                             title = section.get('title', '')
                             body = section.get('content', '')
                             if isinstance(body, list):
                                 body = "<ul>" + "".join([f"<li>{item}</li>" for item in body]) + "</ul>"
                             html_body += f"<h2>{title}</h2><div>{body}</div>"
                         content = html_body
                     else:
                         content = str(content)

                artifact_path = self.pdf_generator.generate_pdf(content, filename)

            else: # Default to DOCX
                artifact_type = "DOCX"
                if not filename.endswith(".docx"): filename += ".docx"
                
                # Ensure content is string
                if not isinstance(content, str): content = str(content)
                artifact_path = self.word_generator.generate_docx(content, filename)
            
            # Get file size
            file_size = os.path.getsize(artifact_path)
            size_str = f"{file_size / 1024:.1f} KB"
            
            yield {
                "type": "artifact",
                "data": {
                    "title": filename,
                    "type": artifact_type,
                    "size": size_str,
                    "path": artifact_path
                }
            }
            
        except Exception as e:
             yield {
                "type": "log",
                "step_title": "Report Generation",
                "content": f"Failed to generate report: {str(e)}"
            }
        
        yield {
             "type": "step_complete",
             "title": "Report Generation",
             "status": "completed"
        }

        yield {
            "type": "final_result",
            "content": "Research task completed successfully."
        }

    def execute_code(self, code: str) -> Dict[str, Any]:
        """Runs code in the isolated sandbox."""
        return sandbox_service.execute_code(self.sandbox_session_id, code)

    def generate_ppt(self, html: str, filename: str) -> str:
        return self.ppt_generator.generate_ppt(html, filename)
        
    def generate_word(self, html: str, filename: str) -> str:
        return self.word_generator.generate_docx(html, filename)

    def cleanup(self):
        """Destroys the sandbox session."""
        sandbox_service.delete_session(self.sandbox_session_id)
