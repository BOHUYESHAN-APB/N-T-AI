from sqlmodel import Session, select
from app.models.database import engine, MoodState
from datetime import datetime, timedelta, timezone
from app.services.llm_service import LLMService

class MoodService:
    def __init__(self):
        self.llm = LLMService()

    def get_current_mood(self, user_id: str) -> str:
        with Session(engine) as session:
            statement = select(MoodState).where(MoodState.user_id == user_id)
            mood = session.exec(statement).first()
            if not mood:
                return "Calm and curious" # Default mood
            
            # Simple regression logic: if last update was long ago, return neutral
            # Use naive UTC time to match DB storage
            now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
            time_diff = now_utc - mood.last_updated
            if time_diff > timedelta(minutes=30):
                return "Calm and curious (Reset due to inactivity)"
            
            return mood.current_mood

    async def update_mood(self, user_id: str, recent_history: list[dict], api_key: str = None, base_url: str = None, model: str = None):
        """
        Updates the mood based on recent interaction.
        """
        current_mood = self.get_current_mood(user_id)
        
        # Construct prompt for Mood Analysis
        prompt = f"""
        Current Mood: {current_mood}
        
        Recent Interaction:
        {recent_history[-3:]} 
        
        Based on the recent interaction and the previous mood, describe the AI's NEW mood in 1 short sentence.
        Focus on emotional shifts (e.g., becoming happier, getting annoyed, feeling empathetic).
        """
        
        new_mood_desc = await self.llm.get_response([{"role": "user", "content": prompt}], api_key, base_url, model)
        
        with Session(engine) as session:
            statement = select(MoodState).where(MoodState.user_id == user_id)
            mood = session.exec(statement).first()
            if not mood:
                mood = MoodState(user_id=user_id, current_mood=new_mood_desc)
            else:
                mood.current_mood = new_mood_desc
                # Use naive UTC time to match DB storage
                mood.last_updated = datetime.now(timezone.utc).replace(tzinfo=None)
            
            session.add(mood)
            session.commit()
        
        return new_mood_desc
