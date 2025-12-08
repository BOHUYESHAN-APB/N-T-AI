import json
import re
import random
from app.services.llm_service import LLMService

# 情感关键词映射，用于快速推断情感
EMOTION_KEYWORDS = {
    'happy': ['haha', 'lol', '哈哈', '开心', '太棒', '有趣', '喜欢', 'great', 'love', 'happy', 'glad', 'wonderful', 'amazing', 'awesome', 'nice', '谢谢', 'thanks', '感谢'],
    'sad': ['伤心', '难过', '抱歉', 'sorry', 'sad', '遗憾', '可惜', 'unfortunately', '没能', '失望'],
    'excited': ['太棒了', '真的吗', '厉害', 'wow', 'amazing', 'incredible', '难以置信', '太厉害', 'excellent'],
    'thinking': ['让我想想', '考虑', 'hmm', '这个问题', '分析', 'think', 'consider', '可能', 'perhaps', 'maybe'],
    'shy': ['害羞', '过奖', '谢谢夸奖', 'blush', '不好意思', 'embarrassed', '您过奖'],
    'confused': ['不确定', '还不清楚', 'confused', 'unclear', '哎', '这个嘛', 'well'],
    'surprised': ['真的', '竟然', '居然', 'really', 'seriously', '我靠', '天哪', 'what', 'omg'],
}

# 动作快捷方式，根据 AI 回复内容触发
ACTION_TRIGGERS = {
    # 问候/打招呼
    'greeting': {
        'keywords': ['你好', '嗨', 'hi', 'hello', '欢迎', '早上好', '下午好', '晚上好', 'good morning', 'good afternoon', 'good evening'],
        'motion': 'CuteWink',  # 用可爱眨眼打招呼
        'expression': 'Happy',
        'parameters': {'ParamAngleX': 10.0, 'ParamMouthForm': 0.8}
    },
    # 点头认同
    'agree': {
        'keywords': ['没错', '对的', '正确', 'yes', 'right', 'exactly', '就是这样', 'indeed', 'absolutely'],
        'motion': 'Nod',
        'expression': None,
        'parameters': {}
    },
    # 摇头否认
    'disagree': {
        'keywords': ['不是', '不对', '错了', 'no', 'wrong', 'incorrect', '不同意', '不行'],
        'motion': 'HeadShake',
        'expression': None,
        'parameters': {}
    },
    # 思考
    'thinking': {
        'keywords': ['让我想想', '我考虑', '这个问题', 'let me think', 'considering', '嗯'],
        'motion': 'ThinkingPose',
        'expression': 'Thinking',
        'parameters': {}
    },
    # 兴奋
    'excited': {
        'keywords': ['太棒了', '厉害', '真棒', 'awesome', 'amazing', 'wonderful', '太好了'],
        'motion': 'HappyBounce',
        'expression': 'Excited',
        'parameters': {}
    },
    # 害羞/谦虚
    'shy': {
        'keywords': ['过奖', '不好意思', '没有没有', '谢谢夸奖', 'flattered', '哪里哪里'],
        'motion': 'ShyBlush',
        'expression': 'Shy',
        'parameters': {}
    },
    # 惊讶
    'surprise': {
        'keywords': ['真的吗', '不会吧', '竟然', '居然', 'really', 'seriously', '天哪', 'what', 'omg'],
        'motion': 'Surprised',
        'expression': 'Surprise',
        'parameters': {}
    },
    # 好奇
    'curious': {
        'keywords': ['为什么', '怎么回事', '什么意思', 'why', 'how come', 'what do you mean', '有意思'],
        'motion': 'Curious',
        'expression': None,
        'parameters': {}
    },
    # 咯咯笑
    'giggle': {
        'keywords': ['哈哈', '嘻嘻', 'haha', 'hehe', 'lol', '好笑', '有趣'],
        'motion': 'Giggle',
        'expression': 'Happy',
        'parameters': {}
    },
    # 不满/嘘嘴
    'pout': {
        'keywords': ['哼', '不开心', '讨厌', '不喜欢', 'hmph', 'annoying', '烦人'],
        'motion': 'Pout',
        'expression': 'Angry',
        'parameters': {}
    },
    # 困倦
    'sleepy': {
        'keywords': ['困了', '想睡', '打哈欠', 'tired', 'sleepy', 'yawn', '累了'],
        'motion': 'Sleepy',
        'expression': None,
        'parameters': {}
    },
}

class MotionAgentService:
    def __init__(self, llm_service: LLMService):
        self.llm_service = llm_service
    
    def _infer_emotion_from_text(self, text: str) -> str:
        """从文本内容推断情感"""
        text_lower = text.lower()
        emotion_scores = {emotion: 0 for emotion in EMOTION_KEYWORDS}
        
        for emotion, keywords in EMOTION_KEYWORDS.items():
            for keyword in keywords:
                if keyword in text_lower:
                    emotion_scores[emotion] += 1
        
        # 返回得分最高的情感
        max_emotion = max(emotion_scores, key=emotion_scores.get)
        return max_emotion if emotion_scores[max_emotion] > 0 else 'neutral'
    
    def _check_action_triggers(self, ai_text: str) -> dict:
        """检查 AI 回复中是否有触发动作的关键词"""
        ai_text_lower = ai_text.lower()
        
        for action_name, action_config in ACTION_TRIGGERS.items():
            for keyword in action_config['keywords']:
                if keyword in ai_text_lower:
                    return {
                        'triggered': True,
                        'action': action_name,
                        'motion': action_config.get('motion'),
                        'expression': action_config.get('expression'),
                        'parameters': action_config.get('parameters', {})
                    }
        
        return {'triggered': False}
    
    def _generate_natural_parameters(self, emotion: str) -> dict:
        """根据情感生成自然的微小动作参数"""
        # 基础微动，让角色更生动
        params = {
            'ParamAngleX': random.uniform(-5, 5),
            'ParamAngleY': random.uniform(-3, 3),
            'ParamAngleZ': random.uniform(-3, 3),
            'ParamBodyAngleX': random.uniform(-2, 2),
        }
        
        # 根据情感调整
        if emotion == 'happy':
            params['ParamMouthForm'] = random.uniform(0.5, 0.8)
            params['ParamAngleY'] = random.uniform(2, 8)  # 略微抬头
        elif emotion == 'sad':
            params['ParamMouthForm'] = random.uniform(-0.5, -0.2)
            params['ParamAngleY'] = random.uniform(-8, -3)  # 低头
            params['ParamBrowLY'] = -0.3
            params['ParamBrowRY'] = -0.3
        elif emotion == 'excited':
            params['ParamMouthForm'] = random.uniform(0.7, 1.0)
            params['ParamMouthOpenY'] = random.uniform(0.2, 0.4)
            params['ParamAngleY'] = random.uniform(5, 10)
        elif emotion == 'thinking':
            params['ParamEyeBallY'] = random.uniform(0.2, 0.5)
            params['ParamEyeBallX'] = random.uniform(-0.3, 0.3)
            params['ParamBrowLY'] = 0.3
            params['ParamBrowRY'] = 0.3
        elif emotion == 'shy':
            params['ParamCheek'] = random.uniform(0.4, 0.7)
            params['ParamEyeBallX'] = random.uniform(-0.4, -0.2)
            params['ParamAngleZ'] = random.uniform(-8, -3)
        elif emotion == 'surprised':
            params['ParamEyeLOpen'] = 1.0
            params['ParamEyeROpen'] = 1.0
            params['ParamBrowLY'] = 0.5
            params['ParamBrowRY'] = 0.5
            params['ParamMouthOpenY'] = random.uniform(0.3, 0.5)
        
        return params

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
        direct_motion = None
        
        # ========== 直接命令快捷方式 ==========
        
        # 眨眼类
        if "一直闭眼" in user_text_lower or "keep eyes closed" in user_text_lower:
            direct_parameters = {"ParamEyeLOpen": 0.0, "ParamEyeROpen": 0.0}
        elif "wink" in user_text_lower or "眨眼" in user_text_lower or "眼笑" in user_text_lower:
            direct_motion = "CuteWink"
        elif "闭眼" in user_text_lower or "close eye" in user_text_lower:
            direct_parameters = {"ParamEyeLOpen": 0.0, "ParamEyeROpen": 0.0}
        
        # 头部动作
        elif "歪头" in user_text_lower or "tilt" in user_text_lower or "head tilt" in user_text_lower:
            direct_motion = "HeadTilt"
        elif "点头" in user_text_lower or "nod" in user_text_lower:
            direct_motion = "Nod"
        elif "摇头" in user_text_lower or "shake" in user_text_lower:
            direct_motion = "HeadShake"
        
        # 表情类
        elif "害羞" in user_text_lower or "shy" in user_text_lower or "脸红" in user_text_lower or "blush" in user_text_lower:
            direct_motion = "ShyBlush"
        elif "笑" in user_text_lower and ("咯咯" in user_text_lower or "嘻嘻" in user_text_lower):
            direct_motion = "Giggle"
        elif "嘘嘴" in user_text_lower or "pout" in user_text_lower or "不开心" in user_text_lower:
            direct_motion = "Pout"
        elif "惊讶" in user_text_lower or "surprise" in user_text_lower:
            direct_motion = "Surprised"
        elif "好奇" in user_text_lower or "curious" in user_text_lower:
            direct_motion = "Curious"
        elif "思考" in user_text_lower or "think" in user_text_lower:
            direct_motion = "ThinkingPose"
        elif "困" in user_text_lower or "sleepy" in user_text_lower or "想睡" in user_text_lower:
            direct_motion = "Sleepy"
        elif "开心" in user_text_lower or "happy" in user_text_lower or "跳" in user_text_lower:
            direct_motion = "HappyBounce"
        
        # 视线方向
        elif "左看" in user_text_lower or "look left" in user_text_lower:
            direct_look_at = {"x": -1.0, "y": 0.0}
            direct_parameters = {"ParamAngleX": -30.0, "ParamEyeBallX": -1.0}
        elif "右看" in user_text_lower or "look right" in user_text_lower:
            direct_look_at = {"x": 1.0, "y": 0.0}
            direct_parameters = {"ParamAngleX": 30.0, "ParamEyeBallX": 1.0}
        elif "上看" in user_text_lower or "抬头" in user_text_lower or "look up" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": 1.0}
            direct_parameters = {"ParamAngleY": 30.0, "ParamEyeBallY": 1.0, "ParamBodyAngleY": 10.0}
        elif "下看" in user_text_lower or "低头" in user_text_lower or "look down" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": -1.0}
            direct_parameters = {"ParamAngleY": -30.0, "ParamEyeBallY": -1.0, "ParamBodyAngleY": -10.0}
        elif "看我" in user_text_lower or "look at me" in user_text_lower or "reset" in user_text_lower:
            direct_look_at = {"x": 0.0, "y": 0.0}
            direct_parameters = {
                "ParamAngleX": 0.0, "ParamAngleY": 0.0, "ParamAngleZ": 0.0,
                "ParamEyeBallX": 0.0, "ParamEyeBallY": 0.0,
                "ParamBodyAngleX": 0.0, "ParamBodyAngleY": 0.0, "ParamBodyAngleZ": 0.0,
                "ParamEyeLOpen": None, "ParamEyeROpen": None
            }
        
        # 如果有直接动作命令
        if direct_motion:
            print(f"[MotionAgent] Direct motion command: {direct_motion}")
            return {
                "motion": direct_motion,
                "expression": None,
                "look_at": None,
                "parameters": None
            }
            
        if direct_parameters or direct_look_at:
            print(f"[MotionAgent] Direct command detected. Skipping LLM. Params: {direct_parameters}")
            return {
                "motion": None,
                "expression": None,
                "look_at": direct_look_at,
                "parameters": direct_parameters
            }
        
        # [Optimization] 检查 AI 回复中的动作触发词，跳过 LLM 调用
        action_trigger = self._check_action_triggers(ai_text)
        if action_trigger.get('triggered'):
            # 从文本推断情感，生成自然参数
            inferred_emotion = self._infer_emotion_from_text(ai_text)
            natural_params = self._generate_natural_parameters(inferred_emotion)
            
            # 合并触发动作的参数
            merged_params = {**natural_params, **action_trigger.get('parameters', {})}
            
            print(f"[MotionAgent] Action trigger detected: {action_trigger['action']}. Skipping LLM.")
            return {
                "motion": action_trigger.get('motion'),
                "expression": action_trigger.get('expression'),
                "look_at": None,
                "parameters": merged_params
            }
        
        # [Optimization] 如果没有特定触发，但能推断出明确情感，也可以跳过 LLM
        inferred_emotion = self._infer_emotion_from_text(ai_text)
        if inferred_emotion != 'neutral':
            natural_params = self._generate_natural_parameters(inferred_emotion)
            print(f"[MotionAgent] Emotion inferred: {inferred_emotion}. Using fast path.")
            return {
                "motion": None,
                "expression": inferred_emotion.capitalize() if inferred_emotion in ['happy', 'sad', 'excited', 'shy', 'surprised', 'thinking'] else None,
                "look_at": None,
                "parameters": natural_params
            }
        
        # If no capabilities are provided, we can't really choose specific files.
        # But we can still return look_at or generic instructions.
        motions_str = ", ".join(motions) if motions else "None (Generic motions only)"
        expressions_str = ", ".join(expressions) if expressions else "None (Generic expressions only)"

        prompt = f"""You are the Motion Director for a lively, expressive Live2D character.
Your job is to make the character feel ALIVE and ENGAGING through motions, expressions, and body language.

**BE PROACTIVE** - Always choose meaningful actions. A character that just stands still is boring!

Context:
User said: "{user_text}"
Character replied: "{ai_text}"
Current Emotion: "{emotion}"

Available Motions: [{motions_str}]
Available Expressions: [{expressions_str}]

Standard Actions (Use if no specific file matches):
- Procedural Motions: [Wink, CuteWink, ShyBlush, HeadTilt, Giggle, Curious, Nod, HeadShake, ThinkingPose, Surprised, HappyBounce, Pout, Sleepy]
- Expressions: [Happy, Sad, Angry, Surprise, Shy, Thinking, Smug, Worried, Excited, Relaxed]

Motion Descriptions:
- Wink: 眨眼 + 歪头 + 微笑
- CuteWink: 可爱眨眼 + 歪头 + 大笑脸 + 脸红 (用于打招呼、调皮)
- ShyBlush: 害羞脸红 + 低头 + 眼球往旁边看 (用于被夸奖、害羞)
- HeadTilt: 好奇歪头 + 睁大眼睛 (用于疑惑、好奇)
- Giggle: 咯咯笑 + 轻微摇动 + 脸红 (用于觉得好笑)
- Curious: 歪头 + 睁大眼睛 + 扬眉 (用于感兴趣)
- Nod: 点头 (用于认同、确认)
- HeadShake: 摇头 (用于否认、不同意)
- ThinkingPose: 思考姿态 + 抬头看上方 + 眉头微皙
- Surprised: 惊讶 + 睁大眼 + 后仰 + 张嘴
- HappyBounce: 开心跳跃 + 笑脸 + 小幅度上下跳动
- Pout: 嘘嘴/不满 + 略微转头
- Sleepy: 困倦 + 缓慢眨眼 + 低头

Live2D Parameters (for fine-grained control, ALWAYS use some for natural movement):
- Head: ParamAngleX (-30~30), ParamAngleY (-30~30), ParamAngleZ (-30~30)
- Body: ParamBodyAngleX (-10~10), ParamBodyAngleY (-10~10), ParamBodyAngleZ (-10~10)
- Eyes: ParamEyeLOpen (0~1), ParamEyeROpen (0~1), ParamEyeBallX (-1~1), ParamEyeBallY (-1~1)
- Brows: ParamBrowLY (-1~1), ParamBrowRY (-1~1), ParamBrowLAngle (-1~1), ParamBrowRAngle (-1~1)
- Mouth: ParamMouthForm (-1~1 sad~smile), ParamMouthOpenY (0~1)
- Cheeks: ParamCheek (0~1 blush intensity)

Behavior Guidelines:
1. **ALWAYS** add subtle parameters for natural body language (head tilts, eye movements)
2. Match intensity to context: excited topics = bigger movements, calm topics = gentle shifts
3. Use look_at to show engagement: look away when thinking, at user when addressing them
4. Add personality: occasional winks, head tilts, eyebrow raises make the character memorable
5. React to keywords: greetings→wave, questions→thinking, jokes→happy+wink, praise→shy+blush

Return a JSON object ONLY, no markdown:
{{
  "motion": "string or null",
  "expression": "string or null", 
  "look_at": {{ "x": float, "y": float }} or null,
  "parameters": {{ "ParamName": float, ... }}
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
            
            # Fallback: 使用智能回退逻辑
            # 1. 尝试从 AI 回复推断情感并生成参数
            inferred_emotion = self._infer_emotion_from_text(ai_text)
            natural_params = self._generate_natural_parameters(inferred_emotion)
            
            # 2. 检查直接命令
            user_text_lower = user_text.lower()
            if "闭眼" in user_text_lower or "close eye" in user_text_lower:
                natural_params["ParamEyeLOpen"] = 0.0
                natural_params["ParamEyeROpen"] = 0.0
            elif "睁眼" in user_text_lower or "open eye" in user_text_lower:
                natural_params["ParamEyeLOpen"] = 1.0
                natural_params["ParamEyeROpen"] = 1.0
            elif "左看" in user_text_lower or "look left" in user_text_lower:
                natural_params["ParamAngleX"] = -30.0
                natural_params["ParamEyeBallX"] = -1.0
            elif "右看" in user_text_lower or "look right" in user_text_lower:
                natural_params["ParamAngleX"] = 30.0
                natural_params["ParamEyeBallX"] = 1.0
            
            # 3. 尝试匹配表情
            fallback_expression = None
            if inferred_emotion != 'neutral':
                expr_name = inferred_emotion.capitalize()
                if expr_name in expressions or any(expr_name.lower() in e.lower() for e in expressions):
                    fallback_expression = expr_name
            
            print(f"[MotionAgent] Using smart fallback. Emotion: {inferred_emotion}, Params: {natural_params}")
            
            return {
                "motion": None,
                "expression": fallback_expression,
                "look_at": None,
                "parameters": natural_params
            }

    async def decide_idle_motion(self, emotion: str, capabilities: dict, 
                               api_key: str = None, base_url: str = None, model: str = None) -> dict:
        """
        Decides a random or context-aware idle motion.
        使用快速路径生成自然的待机动作，避免 LLM 调用延迟。
        """
        # [Optimization] 使用快速路径生成待机动作，不调用 LLM
        # 这样可以更快地响应，让角色更生动
        
        idle_params = {
            # 微小的头部动作
            'ParamAngleX': random.uniform(-8, 8),
            'ParamAngleY': random.uniform(-5, 5),
            'ParamAngleZ': random.uniform(-3, 3),
            # 身体微动
            'ParamBodyAngleX': random.uniform(-3, 3),
            'ParamBodyAngleY': random.uniform(-2, 2),
            # 眼球轻微移动（好奇地看周围）
            'ParamEyeBallX': random.uniform(-0.4, 0.4),
            'ParamEyeBallY': random.uniform(-0.2, 0.3),
        }
        
        # 根据情感调整待机行为
        if emotion == 'happy':
            idle_params['ParamMouthForm'] = random.uniform(0.3, 0.6)
            idle_params['ParamAngleY'] = random.uniform(2, 8)  # 欢快地略微抬头
        elif emotion == 'sad':
            idle_params['ParamMouthForm'] = random.uniform(-0.4, -0.1)
            idle_params['ParamAngleY'] = random.uniform(-8, -3)  # 低头
            idle_params['ParamEyeBallY'] = random.uniform(-0.3, 0)
        elif emotion == 'thinking':
            idle_params['ParamEyeBallY'] = random.uniform(0.3, 0.5)  # 看向上方
            idle_params['ParamBrowLY'] = 0.2
            idle_params['ParamBrowRY'] = 0.2
        elif emotion == 'excited':
            idle_params['ParamMouthForm'] = random.uniform(0.5, 0.8)
            idle_params['ParamAngleX'] = random.uniform(-12, 12)  # 更大的头部动作
        elif emotion == 'shy':
            idle_params['ParamCheek'] = random.uniform(0.3, 0.5)
            idle_params['ParamEyeBallX'] = random.uniform(-0.5, -0.2)  # 略微转移视线
            idle_params['ParamAngleZ'] = random.uniform(-6, -2)
        
        # 随机决定是否眨眼（10% 概率）
        if random.random() < 0.1:
            idle_params['ParamEyeLOpen'] = 0.0
            idle_params['ParamEyeROpen'] = 0.0
        
        # 随机决定是否做一个微笑（15% 概率）
        if random.random() < 0.15 and emotion not in ['sad', 'angry']:
            idle_params['ParamMouthForm'] = random.uniform(0.4, 0.7)
        
        print(f"[MotionAgent] Idle motion generated. Emotion: {emotion}")
        
        return {
            "motion": None,
            "expression": None,
            "look_at": None,
            "parameters": idle_params
        }
