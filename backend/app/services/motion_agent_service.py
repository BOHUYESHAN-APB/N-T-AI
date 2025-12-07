import json
import re
from app.services.llm_service import LLMService

class MotionAgentService:
    def __init__(self, llm_service: LLMService):
        self.llm_service = llm_service

    async def decide_motion(self, user_text: str, ai_text: str, emotion: str, capabilities: dict, 
                          api_key: str = None, base_url: str = None, model: str = None) -> dict:
        """
        Decides the best motion and expression based on context using an LLM Agent.
        
        Args:
            user_text: What the user said.
            ai_text: What the AI replied.
            emotion: The current emotion tag (e.g., 'happy', 'sad').
            capabilities: A dict containing 'motions' (list) and 'expressions' (list).
            api_key: Optional API Key for the LLM.
            base_url: Optional Base URL for the LLM.
            model: Optional Model name for the LLM.
            
        Returns:
            A dict with 'motion', 'expression', and 'look_at'.
        """
        
        motions = capabilities.get('motions', [])
        expressions = capabilities.get('expressions', [])
        
        # [Optimization] Check for direct commands FIRST to avoid LLM latency
        user_text_lower = user_text.lower()
        direct_parameters = None
        direct_look_at = None
        
        if "一直闭眼" in user_text_lower or "keep eyes closed" in user_text_lower:
             # Force close and keep closed
             direct_parameters = {"ParamEyeLOpen": 0.0, "ParamEyeROpen": 0.0}
        elif "闭眼" in user_text_lower or "close eye" in user_text_lower:
            direct_parameters = {"ParamEyeLOpen": 0.0, "ParamEyeROpen": 0.0}
        elif "wink" in user_text_lower or "眨眼" in user_text_lower:
            # Wink: Return a specific motion name "Wink" to trigger procedural animation in frontend
            return {
                "motion": "Wink",
                "expression": None,
                "look_at": None,
                "parameters": None
            }
        elif "左看" in user_text_lower or "look left" in user_text_lower:
            direct_look_at = {"x": -1.0, "y": 0.0}
            direct_parameters = {"ParamAngleX": -30.0, "ParamEyeBallX": -1.0}
        elif "右看" in user_text_lower or "look right" in user_text_lower:
            direct_look_at = {"x": 1.0, "y": 0.0}
            direct_parameters = {"ParamAngleX": 30.0, "ParamEyeBallX": 1.0}
        elif "上看" in user_text_lower or "抬头" in user_text_lower or "look up" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": 1.0}
            # Add BodyAngleY for more obvious movement
            direct_parameters = {"ParamAngleY": 30.0, "ParamEyeBallY": 1.0, "ParamBodyAngleY": 10.0}
        elif "下看" in user_text_lower or "低头" in user_text_lower or "look down" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": -1.0}
            direct_parameters = {"ParamAngleY": -30.0, "ParamEyeBallY": -1.0, "ParamBodyAngleY": -10.0}
        elif "看我" in user_text_lower or "look at me" in user_text_lower or "reset" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": 0.0}
            # Force reset to center (0.0) instead of releasing (None) to ensure it snaps back
            # Keep EyeOpen as None to allow blinking
            direct_parameters = {
                "ParamAngleX": 0.0, "ParamAngleY": 0.0, "ParamAngleZ": 0.0,
                "ParamEyeBallX": 0.0, "ParamEyeBallY": 0.0,
                "ParamBodyAngleX": 0.0, "ParamBodyAngleY": 0.0, "ParamBodyAngleZ": 0.0,
                "ParamEyeLOpen": None, "ParamEyeROpen": None
            }
            
        if direct_parameters or direct_look_at:
            print(f"[MotionAgent] Direct command detected. Skipping LLM. Params: {direct_parameters}")
            return {
                "motion": None,
                "expression": None,
                "look_at": direct_look_at,
                "parameters": direct_parameters
            }
        
        # If no capabilities are provided, we can't really choose specific files.
        # But we can still return look_at or generic instructions.
        motions_str = ", ".join(motions) if motions else "None (Generic motions only)"
        expressions_str = ", ".join(expressions) if expressions else "None (Generic expressions only)"

        prompt = f"""You are the Motion Director for a Live2D character.
Analyze the conversation and determine the best motion and expression.

Context:
User said: "{user_text}"
Character replied: "{ai_text}"
Current Emotion: "{emotion}"

Available Motions: [{motions_str}]
Available Expressions: [{expressions_str}]

Standard Intents (Use these if no specific file matches):
- Motions: [Wink, Wave, Nod, Shake, Idle]
- Expressions: [Happy, Sad, Angry, Surprise, Shy]

Instructions:
1. Select one motion from 'Available Motions' OR 'Standard Intents' that best fits.
2. Select one expression from 'Available Expressions' OR 'Standard Intents' that best fits.
3. Determine if the character should look at a specific direction (look_at).
   - x: -1.0 (left) to 1.0 (right)
   - y: -1.0 (down) to 1.0 (up)
   - 0,0 is center (looking at user).
   - Example: Looking away in shyness might be x=0.5, y=-0.2.
   - If looking at user (default), use null.
4. (Advanced) If no pre-defined motion fits, you can define a custom motion using parameters.
   - This is optional. Only use if 'motion' is null.
   - Parameters: ParamAngleX, ParamAngleY, ParamAngleZ, ParamBodyAngleX, ParamBodyAngleY, ParamBodyAngleZ, ParamEyeLOpen, ParamEyeROpen, ParamBrowLY, ParamBrowRY, ParamMouthForm, ParamMouthOpenY.
   - Values are typically -30 to 30 for angles, 0 to 1 for open/close.

Return a JSON object ONLY, no markdown formatting:
{{
  "motion": "string or null",
  "expression": "string or null",
  "look_at": {{ "x": float, "y": float }} or null,
  "parameters": {{ "ParamName": float, ... }} or null
}}
"""

        try:
            # Call LLM
            # We use a lower temperature for deterministic JSON output
            print(f"[MotionAgent] Sending prompt to LLM...")
            response_text = await self.llm_service.analyze_text(
                text="", # Context is already in prompt
                prompt=prompt,
                api_key=api_key,
                base_url=base_url,
                model=model
            )
            print(f"[MotionAgent] Raw LLM Response: {response_text}")
            
            # Parse JSON
            # Clean up potential markdown code blocks
            cleaned_text = re.sub(r'```json\s*|\s*```', '', response_text).strip()
            result = json.loads(cleaned_text)
            
            # Validate against capabilities (Double check)
            if result.get('motion') and result['motion'] not in motions:
                # If LLM hallucinated a motion, try to find a partial match or discard
                # For now, we discard to avoid errors
                result['motion'] = None
                
            if result.get('expression') and result['expression'] not in expressions:
                result['expression'] = None
                
            return result

        except Exception as e:
            print(f"MotionAgent Error: {e}")
            
            # Fallback: Simple keyword matching for debugging and robustness
            # This ensures that even if the LLM fails, basic commands work.
            fallback_parameters = None
            fallback_look_at = None
            
            user_text_lower = user_text.lower()
            if "闭眼" in user_text_lower or "close eye" in user_text_lower:
                fallback_parameters = {"ParamEyeLOpen": 0.0, "ParamEyeROpen": 0.0}
            elif "睁眼" in user_text_lower or "open eye" in user_text_lower:
                fallback_parameters = {"ParamEyeLOpen": 1.0, "ParamEyeROpen": 1.0}
            elif "左看" in user_text_lower or "look left" in user_text_lower:
                fallback_look_at = {"x": -1.0, "y": 0.0}
                fallback_parameters = {"ParamAngleX": -30.0, "ParamEyeBallX": -1.0}
            elif "右看" in user_text_lower or "look right" in user_text_lower:
                fallback_look_at = {"x": 1.0, "y": 0.0}
                fallback_parameters = {"ParamAngleX": 30.0, "ParamEyeBallX": 1.0}
            
            # Fallback: Use the emotion as the motion/expression key if it exists in capabilities
            fallback_motion = emotion if emotion in motions else None
            fallback_expression = emotion if emotion in expressions else None
            
            print(f"[MotionAgent] Using fallback logic. Params: {fallback_parameters}")
            
            return {
                "motion": fallback_motion,
                "expression": fallback_expression,
                "look_at": fallback_look_at,
                "parameters": fallback_parameters
            }

    async def decide_idle_motion(self, emotion: str, capabilities: dict, 
                               api_key: str = None, base_url: str = None, model: str = None) -> dict:
        """
        Decides a random or context-aware idle motion.
        """
        motions = capabilities.get('motions', [])
        expressions = capabilities.get('expressions', [])
        
        motions_str = ", ".join(motions) if motions else "None (Generic motions only)"
        expressions_str = ", ".join(expressions) if expressions else "None (Generic expressions only)"

        prompt = f"""You are the Motion Director for a Live2D character.
The character is currently IDLE (waiting for user input).
Current Emotion: "{emotion}"

Available Motions: [{motions_str}]
Available Expressions: [{expressions_str}]

Instructions:
1. Select a subtle motion suitable for idling (e.g., breathing, looking around, slight adjustments).
2. Avoid high-energy motions unless the emotion is very intense.
3. You can suggest looking at random directions (look_at).

Return a JSON object ONLY:
{{
  "motion": "string or null",
  "expression": "string or null",
  "look_at": {{ "x": float, "y": float }} or null,
  "parameters": {{ "ParamName": float, ... }} or null
}}
"""
        try:
            response_text = await self.llm_service.analyze_text(
                text="",
                prompt=prompt,
                api_key=api_key,
                base_url=base_url,
                model=model
            )
            cleaned_text = re.sub(r'```json\s*|\s*```', '', response_text).strip()
            result = json.loads(cleaned_text)
            return result
        except Exception as e:
            print(f"Idle Motion Error: {e}")
            return {"motion": None, "expression": None, "look_at": None, "parameters": None}
