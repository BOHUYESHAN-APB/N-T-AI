
import os
from typing import Dict, Any, List, Union
from app.skills.common.document_skill.scripts.ppt_generator import PPTGenerator
from app.skills.common.document_skill.scripts.word_generator import WordGenerator
from app.skills.common.document_skill.scripts.excel_generator import ExcelGenerator, excel_generator as default_excel_gen

class UnifiedOfficeTool:
    """
    Unified interface for generating Office documents (PPT, Doc, Excel).
    Inspired by Skywork-Super-Agents' office_tool.
    """
    def __init__(self, output_dir: str = "app/static/reports"):
        self.output_dir = output_dir
        self.ppt_generator = PPTGenerator(output_dir=output_dir)
        self.word_generator = WordGenerator(output_dir=output_dir)
        self.excel_generator = default_excel_gen # Uses the singleton instance or create new if needed
        # Overwrite output dir for excel if needed, but the singleton might be fixed.
        # Better to re-instantiate if the class supports it.
        self.excel_generator = ExcelGenerator(output_dir=output_dir)

    def generate_file(self, file_type: str, content: Union[str, List[Dict]], filename: str) -> str:
        """
        Generates a file based on type.
        
        Args:
            file_type: "ppt", "docx", "excel", "pdf"
            content: HTML string for PPT/Docx, List of Dicts for Excel.
            filename: Desired filename.
            
        Returns:
            Absolute path to the generated file.
        """
        try:
            if file_type in ["ppt", "pptx", "slides"]:
                if not filename.endswith(".pptx"):
                    filename += ".pptx"
                return self.ppt_generator.generate_ppt(content, filename)

            elif file_type in ["doc", "docx", "word"]:
                if not filename.endswith(".docx"):
                    filename += ".docx"
                return self.word_generator.generate_docx(content, filename)

            elif file_type in ["excel", "sheet", "xlsx"]:
                if not filename.endswith(".xlsx"):
                    filename += ".xlsx"
                return self.excel_generator.generate_excel(content, filename)
                
            else:
                raise ValueError(f"Unsupported file type: {file_type}")
                
        except Exception as e:
            print(f"Error in UnifiedOfficeTool: {e}")
            raise e
            
    # Wrapper methods for specific types to match Skywork style
    def generate_ppt(self, content: str, filename: str) -> str:
        return self.ppt_generator.generate_ppt(content, filename)

    def generate_doc(self, content: str, filename: str) -> str:
        return self.word_generator.generate_docx(content, filename)
        
    def generate_sheet(self, content: List[Dict], filename: str) -> str:
        return self.excel_generator.generate_excel(content, filename)

