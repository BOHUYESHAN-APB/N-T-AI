"""
Academic Search Tool
Wraps ArXiv API to provide academic paper search.
Can be extended to support Google Scholar via SERP API or similar.
"""

import arxiv
from typing import List, Dict, Any

class AcademicSearch:
    def __init__(self):
        pass

    def search(self, query: str, max_results: int = 5) -> List[Dict[str, str]]:
        """
        Performs an academic search using ArXiv.
        """
        results = []
        try:
            # Construct client
            client = arxiv.Client()
            
            search = arxiv.Search(
                query=query,
                max_results=max_results,
                sort_by=arxiv.SortCriterion.Relevance
            )

            for r in client.results(search):
                results.append({
                    "title": r.title,
                    "href": r.entry_id,
                    "body": f"Published: {r.published.year}. Summary: {r.summary[:300]}...",
                    "authors": ", ".join([a.name for a in r.authors[:3]]),
                    "source": "ArXiv"
                })
                
        except Exception as e:
            print(f"Academic search error: {e}")
            return [{"error": str(e)}]
            
        return results

academic_search = AcademicSearch()
