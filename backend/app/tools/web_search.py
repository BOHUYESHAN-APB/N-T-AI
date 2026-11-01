"""
Web Search Tool
Wraps duckduckgo-search (ddgs) to provide search capabilities.
"""

from typing import List, Dict, Any
from ddgs import DDGS

class WebSearch:
    def __init__(self):
        self.ddgs = DDGS()

    def search(self, query: str, max_results: int = 5) -> List[Dict[str, str]]:
        """
        Performs a web search and returns a list of results.
        """
        results = []
        try:
            # text() is the main search method in newer versions
            # results generator
            search_results = self.ddgs.text(query, max_results=max_results)
            if search_results:
                for r in search_results:
                    results.append({
                        "title": r.get("title", ""),
                        "href": r.get("href", ""),
                        "body": r.get("body", "")
                    })
        except Exception as e:
            print(f"Search error: {e}")
            return [{"error": str(e)}]
            
        return results

web_search = WebSearch()
