from sqlmodel import Session, select
from app.models.database import engine, Jargon

class JargonService:
    def search_jargon(self, text: str) -> list[Jargon]:
        """
        Scans the text for known jargon terms.
        """
        found_jargon = []
        with Session(engine) as session:
            # In a real app, we might use a more efficient search (e.g. Aho-Corasick or FTS)
            # For now, we just iterate all jargon (assuming small DB) or search for specific keywords if we had them.
            # Let's do a simple 'contains' check for all verified jargon.
            statement = select(Jargon).where(Jargon.is_verified == True)
            all_jargon = session.exec(statement).all()
            
            for jargon in all_jargon:
                if jargon.term in text:
                    found_jargon.append(jargon)
        return found_jargon

    def add_candidate_jargon(self, term: str, context: str):
        with Session(engine) as session:
            statement = select(Jargon).where(Jargon.term == term)
            existing = session.exec(statement).first()
            if existing:
                existing.frequency += 1
                session.add(existing)
            else:
                new_jargon = Jargon(term=term, definition="Pending analysis", context_example=context)
                session.add(new_jargon)
            session.commit()

    def get_jargon_context(self, text: str) -> str:
        """Returns a string explaining any jargon found in the text."""
        jargons = self.search_jargon(text)
        if not jargons:
            return ""
        
        context = "Detected Jargon/Terms:\n"
        for j in jargons:
            context += f"- {j.term}: {j.definition}\n"
        return context
