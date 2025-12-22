from sqlmodel import Session, select
from app.models.database import engine, ExpressionStyle

class ExpressionService:
    def get_style_suggestion(self, context_text: str) -> str:
        """
        Returns a style suggestion if the context matches a known situation.
        For now, this is a simple keyword match or random selection for demonstration.
        """
        with Session(engine) as session:
            statement = select(ExpressionStyle)
            styles = session.exec(statement).all()
            
            if not styles:
                return ""

            # Simple logic: if any situation keyword is in context, suggest that style
            for style in styles:
                if style.situation in context_text:
                    return f"Try to reply in this style: {style.style}"
            
            return ""

    def add_style(self, situation: str, style: str):
        with Session(engine) as session:
            new_style = ExpressionStyle(situation=situation, style=style)
            session.add(new_style)
            session.commit()
