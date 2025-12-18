from typing import List, Dict, Any
import os
import json
from openai import AsyncOpenAI
from app.tools.office_suite import PPTGenerator, WordGenerator, PDFGenerator, OfficeProcessor
from .utils import normalize_output_format, parse_writer_output_files

class Writer:
    def __init__(self, config: Dict[str, Any], output_dir: str = "app/static/reports"):
        self.config = config
        self.output_dir = output_dir
        self.ppt_generator = PPTGenerator(output_dir=output_dir)
        self.word_generator = WordGenerator(output_dir=output_dir)
        self.pdf_generator = PDFGenerator(output_dir=output_dir)
        self.office_processor = OfficeProcessor(output_dir=output_dir)

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

    async def generate_document(self, user_input: str, research_log: str, requested_formats: List[str], current_date: str) -> List[Dict[str, Any]]:
        client = self._get_client()
        model = self._get_model()

        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        prompts_dir = os.path.join(base_dir, "prompts")
        
        with open(os.path.join(prompts_dir, "writer.system.txt"), "r", encoding="utf-8") as f:
            sys_template = f.read()
        with open(os.path.join(prompts_dir, "writer.user.txt"), "r", encoding="utf-8") as f:
            user_template = f.read()

        sys_prompt = sys_template.replace("{{current_date}}", current_date)
        user_prompt = user_template.replace("{{user_input}}", user_input)\
                                   .replace("{{research_log}}", research_log)\
                                   .replace("{{requested_formats}}", ", ".join(requested_formats))

        response = await client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={"type": "json_object"}
        )
        
        writer_response = response.choices[0].message.content
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
                if fmt == "ppt":
                    full_path = self.ppt_generator.generate_ppt(content, filename)
                elif fmt == "docx":
                    full_path = self.word_generator.generate_docx(content, filename)
                elif fmt == "pdf":
                    # full_path = self.pdf_generator.generate(content, filename)
                    full_path = self.word_generator.generate_docx(content, filename) # Fallback to docx
                elif fmt == "excel":
                    # Assuming excel_generator is available or handled by OfficeProcessor
                    # For now, let's use a placeholder if specific excel generator isn't injected
                    from app.skills.common.document_skill.scripts.excel_generator import excel_generator
                    full_path = excel_generator.generate(content, filename)
                else:
                    # Default to docx
                    full_path = self.word_generator.generate_docx(content, filename)
                
                results.append({
                    "filename": os.path.basename(full_path),
                    "path": full_path,
                    "type": fmt
                })
            except Exception as e:
                print(f"Error generating {fmt} file: {e}")
                
        return results
