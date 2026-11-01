from typing import List, Dict, Any, Tuple, Optional
import os
from openai import AsyncOpenAI
from app.tools.office_suite import OfficeProcessor
from app.tools.unified_office import UnifiedOfficeTool
from .utils import normalize_output_format, parse_writer_output_files

from app.services.rag_service import TempRAGSession
from app.core.config import REPORTS_DIR

class Writer:
    def __init__(self, config: Dict[str, Any], output_dir: str = str(REPORTS_DIR), rag_session: Optional[TempRAGSession] = None):
        self.config = config
        self.output_dir = output_dir
        self.office_tool = UnifiedOfficeTool(output_dir=output_dir)
        self.office_processor = OfficeProcessor(output_dir=output_dir)
        self.rag_session = rag_session

    def _get_client(self) -> AsyncOpenAI:
        role_config = self.config.get("writer") or {}
        api_key = role_config.get("api_key") or os.getenv("OPENAI_API_KEY")
        base_url = role_config.get("base_url") or os.getenv("OPENAI_BASE_URL")
        
        if not api_key:
            from app.core.config import settings
            api_key = settings.OPENAI_API_KEY
            base_url = settings.OPENAI_BASE_URL

        if not api_key:
             raise ValueError("No API Key provided for writer role")

        return AsyncOpenAI(api_key=api_key, base_url=base_url)

    def _get_model(self) -> str:
        role_config = self.config.get("writer") or {}
        return role_config.get("model") or "gpt-3.5-turbo"

    async def generate_document(self, user_input: str, research_log: str, requested_formats: List[str], current_date: str) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        client = self._get_client()
        model = self._get_model()

        # Search RAG for extra context
        rag_context = ""
        if self.rag_session:
            try:
                # Query RAG for the most relevant bits from files and logs
                rag_results = await self.rag_session.search(user_input, top_k=8)
                if rag_results:
                    rag_context = "\n[Additional Context from Local Files/Logs]:\n"
                    for r in rag_results:
                        rag_context += f"- {r['content']}\n"
            except Exception as e:
                print(f"Error searching RAG in Writer: {e}")

        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        prompts_dir = os.path.join(base_dir, "prompts")
        
        with open(os.path.join(prompts_dir, "writer.system.txt"), "r", encoding="utf-8") as f:
            sys_template = f.read()
        with open(os.path.join(prompts_dir, "writer.user.txt"), "r", encoding="utf-8") as f:
            user_template = f.read()

        from .utils import truncate_text
        
        sys_prompt = sys_template.replace("{{current_date}}", current_date)
        user_prompt = user_template.replace("{{user_input}}", user_input)\
                                   .replace("{{research_log}}", truncate_text(research_log + "\n" + rag_context, 25000))\
                                   .replace("{{requested_formats}}", ", ".join(requested_formats))

        messages = [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": user_prompt}
        ]

        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            response_format={"type": "json_object"}
        )
        
        writer_response = response.choices[0].message.content
        
        debug_info = {
            "agent": "Writer",
            "model": model,
            "messages": messages,
            "response": writer_response
        }
        
        output_files = parse_writer_output_files(writer_response, user_input)
        
        # Generate actual files
        results = []
        for file_data in output_files:
            fmt = normalize_output_format(file_data.get("format"))
            content = file_data.get("content") or ""
            filename = file_data.get("filename") or "report"
            
            # Ensure filename has extension
            if not filename.endswith(f".{fmt}") and fmt != "excel":
                filename += f".{fmt}"
            elif fmt == "excel" and not filename.endswith(".xlsx"):
                filename += ".xlsx"

            full_path = ""
            try:
                # Use UnifiedOfficeTool for all generations
                # Map formats to what UnifiedOfficeTool expects if needed
                if fmt == "pdf":
                    # Fallback to docx for PDF as before, or handle inside UnifiedOfficeTool
                    # UnifiedOfficeTool handles 'doc', 'docx'
                    # We can ask it to generate docx and then maybe convert, but for now just docx
                    full_path = self.office_tool.generate_file("docx", content, filename)
                else:
                    full_path = self.office_tool.generate_file(fmt, content, filename)
                
                results.append({
                    "filename": os.path.basename(full_path),
                    "path": full_path,
                    "type": fmt,
                    "content": content
                })
            except Exception as e:
                # Log error or add to results with error status
                print(f"Error generating {fmt}: {e}")
                
        return results, debug_info
