"""
Academic Search Tool
Wraps ArXiv API to provide academic paper search.
Can be extended to support Google Scholar via SERP API or similar.
"""

from typing import List, Dict
from urllib.parse import quote_plus
import xml.etree.ElementTree as ET

import httpx

class AcademicSearch:
    def __init__(self):
        pass

    def search(self, query: str, max_results: int = 5) -> List[Dict[str, str]]:
        """
        Performs an academic search using ArXiv.
        """
        results: List[Dict[str, str]] = []
        try:
            q = (query or "").strip()
            if not q:
                return []

            n = max(1, min(int(max_results or 5), 20))
            url = (
                "https://export.arxiv.org/api/query"
                f"?search_query=all:{quote_plus(q)}"
                f"&start=0&max_results={n}&sortBy=relevance&sortOrder=descending"
            )
            headers = {
                "User-Agent": "N-T-AI/DeepResearch (+https://arxiv.org/help/api/)",
                "Accept": "application/atom+xml, text/xml;q=0.9, */*;q=0.1",
            }
            resp = httpx.get(url, headers=headers, timeout=12.0)
            resp.raise_for_status()

            ns = {"atom": "http://www.w3.org/2005/Atom"}
            root = ET.fromstring(resp.text)

            for entry in root.findall("atom:entry", ns):
                title = (entry.findtext("atom:title", default="", namespaces=ns) or "").strip()
                title = " ".join(title.split())

                summary = (entry.findtext("atom:summary", default="", namespaces=ns) or "").strip()
                summary = " ".join(summary.split())

                published = (entry.findtext("atom:published", default="", namespaces=ns) or "").strip()
                year = published[:4] if len(published) >= 4 else ""

                href = ""
                for link in entry.findall("atom:link", ns):
                    if link.attrib.get("rel") == "alternate" and link.attrib.get("href"):
                        href = link.attrib["href"]
                        break
                if not href:
                    href = (entry.findtext("atom:id", default="", namespaces=ns) or "").strip()

                authors = []
                for author in entry.findall("atom:author", ns):
                    name = (author.findtext("atom:name", default="", namespaces=ns) or "").strip()
                    if name:
                        authors.append(name)
                authors_text = ", ".join(authors[:3])

                body_parts = []
                if year:
                    body_parts.append(f"Published: {year}.")
                if authors_text:
                    body_parts.append(f"Authors: {authors_text}.")
                if summary:
                    body_parts.append(f"Summary: {summary[:300]}...")
                body = " ".join(body_parts).strip()

                if title and href:
                    results.append(
                        {
                            "title": title,
                            "href": href,
                            "body": body,
                            "authors": authors_text,
                            "source": "ArXiv",
                        }
                    )
        except Exception as e:
            return [{"error": str(e)}]
            
        return results

academic_search = AcademicSearch()
