from typing import List, Dict, Any, Optional
import re
import httpx
import os
from openai import AsyncOpenAI
from app.services.search_service import SearchService

class Researcher:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.search_service = SearchService()

    def _get_client(self) -> AsyncOpenAI:
        role_config = self.config.get("researcher") or {}
        api_key = role_config.get("api_key") or os.getenv("OPENAI_API_KEY")
        base_url = role_config.get("base_url") or os.getenv("OPENAI_BASE_URL")
        
        if not api_key:
            from app.core.config import settings
            api_key = settings.OPENAI_API_KEY
            base_url = settings.OPENAI_BASE_URL

        if not api_key:
             raise ValueError("No API Key provided for researcher role")

        return AsyncOpenAI(api_key=api_key, base_url=base_url)

    def _get_model(self) -> str:
        role_config = self.config.get("researcher") or {}
        return role_config.get("model") or "gpt-3.5-turbo"

    def build_search_queries(self, base_query: str, user_input: str) -> List[str]:
        base_query = (base_query or "").strip()
        if not base_query:
            base_query = user_input.strip()

        candidates = [
            base_query,
            f"{base_query} 最新",
            f"{base_query} 数据 统计",
            f"{base_query} 报告 2025",
            f"{base_query} 产品 发布",
        ]
        fallback_candidates = [
            f"{base_query} 论文 arxiv",
            f"{base_query} site:arxiv.org",
            f"{base_query} 知网 cnki",
            f"{base_query} SCI Web of Science",
        ]

        seen = set()
        queries: List[str] = []
        for q in candidates:
            q = re.sub(r"\s+", " ", (q or "").strip())
            if not q: continue
            if q in seen: continue
            seen.add(q)
            queries.append(q)

        for q in fallback_candidates:
            if len(queries) >= 4: break
            q = re.sub(r"\s+", " ", (q or "").strip())
            if not q or q in seen: continue
            seen.add(q)
            queries.append(q)

        if len(queries) < 3:
            for suffix in ["趋势", "对比", "行业 研究"]:
                if len(queries) >= 3: break
                q = re.sub(r"\s+", " ", f"{base_query} {suffix}".strip())
                if q and q not in seen:
                    seen.add(q)
                    queries.append(q)

        return queries[: max(3, min(4, len(queries)))]

    async def can_access_url(self, url: str) -> bool:
        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
            async with httpx.AsyncClient(timeout=6.0, follow_redirects=True, verify=False) as client:
                resp = await client.get(url, headers=headers)
            return resp.status_code >= 200 and resp.status_code < 500
        except Exception:
            return False

    async def run_data_analysis(self, context: str, requirement: str) -> str:
        """Generates and executes analysis code."""
        try:
            # 1. Generate Code
            code = await self.code_generator.generate_analysis_code(context, requirement)
            
            # 2. Inject Visualizer
            full_code = f"{self.visualizer_code}\n\n# Generated Analysis\n{code}"
            
            # 3. Execute in Sandbox
            result = sandbox_service.execute_code(self.sandbox_session_id, full_code)
            
            output_msg = "Analysis Execution:\n"
            if result["success"]:
                output_msg += "Success.\n"
                if result["output"]:
                    output_msg += f"Output:\n{result['output']}\n"
                
                # Check for generated images
                workspace_dir = result.get("workspace")
                if workspace_dir:
                    chart_path = os.path.join(workspace_dir, "chart_output.png")
                    if os.path.exists(chart_path):
                        output_msg += f"[Generated Chart: {chart_path}]\n"
            else:
                output_msg += f"Failed: {result['error']}\n"
                
            return output_msg
        except Exception as e:
            return f"Error during data analysis: {str(e)}"

    async def execute_step(self, step_description: str, user_input: str, current_date: str, depth: str = "Medium", min_sources: int = 0) -> str:
        import json
        
        # 0. Check for Restricted Sources (CNKI, etc.)
        restricted_keywords = ["CNKI", "知网", "Wanfang", "万方", "VIP", "维普"]
        if any(k in step_description for k in restricted_keywords) or any(k in user_input for k in restricted_keywords):
             return f"Action Required: The requested sources ({', '.join(restricted_keywords)}) usually require manual access or institutional login. Please manually search for '{step_description}' and upload the relevant documents."

        # 1. Determine Iterations based on Depth
        iterations = 1
        if depth == "High":
            iterations = 2
        elif depth == "Professional":
            iterations = 4 # Will loop internally to find more sources
        
        all_results = []
        collected_sources = set()
        
        # Initial Query Build
        queries = self.build_search_queries(step_description, user_input)
        
        for i in range(iterations):
            step_results = ""
            for q in queries:
                try:
                    # Professional mode might need deeper search
                    limit = 5 if depth == "Professional" else 3
                    results = await self.search_service.search(q, limit=limit)
                    
                    for r in results:
                        if r.get('url'):
                            collected_sources.add(r['url'])
                    
                    step_results += f"Query: {q}\nResults:\n{json.dumps(results, ensure_ascii=False, indent=2)}\n\n"
                except Exception as e:
                    step_results += f"Error searching {q}: {str(e)}\n"
            
            all_results.append(step_results)
            
            # If we have enough sources, break
            if min_sources > 0 and len(collected_sources) >= min_sources:
                break
                
            # If Professional, generate new queries based on previous results (Simple Feedback Loop)
            if depth == "Professional" and i < iterations - 1:
                # In a real system, we'd use LLM to generate next queries.
                # Here, we just append a modifier to dig deeper
                queries = [f"{q} related papers" for q in queries[:2]]

        search_results_text = "\n".join(all_results)

        # 2. Data Analysis (Optional)
        # Check if we need to visualize data
        if "analyze" in step_description.lower() or "visualize" in step_description.lower() or "plot" in step_description.lower():
             analysis_result = await self.run_data_analysis(search_results_text, step_description)
             search_results_text += f"\n\n{analysis_result}"

        # 3. Summarize/Analyze with LLM
        client = self._get_client()
        model = self._get_model()

        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        prompts_dir = os.path.join(base_dir, "prompts")
        
        with open(os.path.join(prompts_dir, "researcher.system.txt"), "r", encoding="utf-8") as f:
            sys_template = f.read()
        with open(os.path.join(prompts_dir, "researcher.user.txt"), "r", encoding="utf-8") as f:
            user_template = f.read()

        sys_prompt = sys_template.replace("{{current_date}}", current_date)
        user_prompt = user_template.replace("{{step_description}}", step_description)\
                                   .replace("{{user_input}}", user_input)\
                                   .replace("{{search_results}}", search_results_text)

        response = await client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": user_prompt}
            ]
        )
        return response.choices[0].message.content
