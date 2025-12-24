from sqlmodel import Session, select
from app.models.database import engine, ExpressionStyle
from typing import Dict, Any

class ExpressionService:
    def __init__(self):
        # 预设的表情参数映射
        self.preset_expressions = {
            "happy": {
                "mouth": 0.8,
                "eyes": 1.0,
                "eyebrow": 0.8,
                "blush": 0.3,
                "pupilX": 0.0,
                "pupilY": 0.0,
                "headTilt": 5.0,
                "headX": 5.0,
                "headY": 2.0
            },
            "sad": {
                "mouth": 0.1,
                "eyes": 0.4,
                "eyebrow": -0.5,
                "blush": 0.0,
                "pupilX": 0.0,
                "pupilY": -0.4,
                "headTilt": -8.0,
                "headX": -3.0,
                "headY": -10.0
            },
            "angry": {
                "mouth": 0.2,
                "eyes": 0.6,
                "eyebrow": -0.8,
                "blush": 0.5,
                "pupilX": 0.0,
                "pupilY": 0.0,
                "headTilt": 0.0,
                "headX": 0.0,
                "headY": 5.0
            },
            "surprised": {
                "mouth": 0.9,
                "eyes": 1.0,
                "eyebrow": 0.6,
                "blush": 0.0,
                "pupilX": 0.0,
                "pupilY": 0.2,
                "headTilt": -10.0,
                "headX": 0.0,
                "headY": 10.0
            },
            "thinking": {
                "mouth": 0.0,
                "eyes": 1.0,
                "eyebrow": 0.4,
                "blush": 0.0,
                "pupilX": 0.0,
                "pupilY": 0.6,
                "headTilt": 8.0,
                "headX": -5.0,
                "headY": 5.0
            }
        }

    def get_expression_from_text(self, text: str) -> Dict[str, float]:
        """根据文本内容猜测表情参数"""
        text = text.lower()
        
        # 简单的关键词匹配逻辑
        if any(k in text for k in ["哈哈", "开心", "真棒", "太好了", "happy", "lol", "great"]):
            return self.preset_expressions["happy"]
        elif any(k in text for k in ["难过", "伤心", "遗憾", "抱歉", "sad", "sorry", "unfortunate"]):
            return self.preset_expressions["sad"]
        elif any(k in text for k in ["可恶", "生气", "滚", "闭嘴", "angry", "shut up", "hate"]):
            return self.preset_expressions["angry"]
        elif any(k in text for k in ["哇", "真的吗", "惊讶", "天哪", "wow", "really", "surprised"]):
            return self.preset_expressions["surprised"]
        
        # 默认返回中性/思考状态
        return self.preset_expressions["thinking"]

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
