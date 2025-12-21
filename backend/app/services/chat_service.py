import json
from sqlmodel import Session, select
from app.models.database import engine, Conversation, Memory
from app.services.llm_service import LLMService
from app.services.person_service import PersonService
from app.services.mood_service import MoodService
from app.services.memory_system_service import MemorySystemService
from app.services.expression_service import ExpressionService
from app.services.search_service import SearchService
from app.services.audio_service import AudioService
from app.services.meme_service import MemeService
from app.api.routes.live2d_routes import manager as live2d_manager
from app.core.prompts import FIREFLY_PERSONA, FIREFLY_PERSONA_BASIC, FIREFLY_PERSONA_ADVANCED, FIREFLY_PERSONA_FULL, MEMORY_EXTRACTION_PROMPT, AGENT_INSTRUCTIONS
from app.core.logger import logger
from fastapi import BackgroundTasks
import asyncio
import base64

from typing import Union, List, Dict, Any, Optional
import re
import ast
import os
from pathlib import Path
from datetime import datetime

from app.core.config import settings
from app.tools.academic_search import academic_search
import httpx

class ChatService:
    def __init__(self):
        self.llm = LLMService()
        self.person_service = PersonService()
        self.mood_service = MoodService()
        self.memory_system = MemorySystemService()
        self.expression_service = ExpressionService()
        self.search_service = SearchService()
        self.audio_service = AudioService() # Initialize Audio Service
        self.meme_service = MemeService()

    def _sanitize_text_for_tts(self, text: str) -> str:
        s = text or ""
        s = re.sub(r"```[\s\S]*?```", "", s)
        s = re.sub(r"\[IMAGE:[^\]]*\]", "", s)
        s = re.sub(r"\[TOOL_CALL\][\s\S]*?(\n|$)", "", s)
        s = re.sub(r"\[TOOL_RESULT\][\s\S]*?(\n|$)", "", s)
        s = re.sub(r"\[System[^\]]*\]", "", s)
        lines = []
        for line in s.splitlines():
            t = line.strip()
            if not t:
                continue
            if t.startswith("注："):
                continue
            if re.match(r"^\(.*\)$", t):
                continue
            lines.append(line)
        s = "\n".join(lines)
        return s.strip()

    def _strip_inner_monologue_text(self, text: str) -> str:
        s = text or ""
        s = re.sub(r"（[^）]*）", "", s, flags=re.DOTALL)

        def repl(m: re.Match) -> str:
            inner = (m.group(1) or "").strip()
            has_cjk = re.search(r"[\u4e00-\u9fff]", inner) is not None
            if has_cjk and len(inner) <= 40:
                return ""
            return m.group(0) or ""

        s = re.sub(r"(?<!\])\(([^)]*)\)", repl, s, flags=re.DOTALL)
        s = re.sub(r"[ \t]+\n", "\n", s)
        s = re.sub(r"\n{3,}", "\n\n", s)
        return s.strip()

    def _parse_tool_kwargs(self, args_str: str) -> Dict[str, Any]:
        raw = (args_str or "").strip()
        if not raw:
            return {}
        try:
            tree = ast.parse(f"f({raw})", mode="eval")
            call = tree.body
            if not isinstance(call, ast.Call):
                return {}
            kwargs: Dict[str, Any] = {}
            for kw in call.keywords:
                if not kw.arg:
                    continue
                try:
                    kwargs[kw.arg] = ast.literal_eval(kw.value)
                except Exception:
                    kwargs[kw.arg] = None
            return kwargs
        except Exception:
            kwargs: Dict[str, Any] = {}
            matches = re.findall(r'(\w+)=["\'](.*?)["\']', raw)
            for key, value in matches:
                kwargs[key] = value
            return kwargs

    async def _skywork_generate_file_url(self, file_type: str, query: str) -> Optional[str]:
        api_key = os.getenv("SKYWORK_API_KEY")
        if not api_key:
            return None
        gen_url = "https://api-cn.tiangong.cn/infra/tool/generate_file"
        params = {"api_key": api_key, "query": query, "file_type": file_type}
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(gen_url, params=params)
            resp.raise_for_status()
            payload = resp.json()
            if payload.get("code") != 200:
                return None
            data = payload.get("data") or {}
            url = (data.get("url") or "").strip()
            return url or None

    async def _download_to_reports(self, url: str, filename: str) -> str:
        safe_name = re.sub(r"[^a-zA-Z0-9._-]+", "_", (filename or "").strip())
        safe_name = safe_name.strip("._")
        if not safe_name:
            safe_name = f"file_{int(datetime.now().timestamp())}"

        reports_dir = Path("app/static/reports")
        reports_dir.mkdir(parents=True, exist_ok=True)
        target_path = reports_dir / safe_name

        async with httpx.AsyncClient(timeout=180) as client:
            resp = await client.get(url, follow_redirects=True)
            resp.raise_for_status()
            target_path.write_bytes(resp.content)
        return str(target_path)

    def _split_into_chunks(self, text: str) -> List[str]:
        units = []
        parts = re.split(r"([。！？!?\.])", text)
        cur = ""
        for p in parts:
            if re.match(r"[。！？!?\.]", p):
                cur += p
                if cur.strip():
                    units.append(cur.strip())
                cur = ""
            else:
                cur += p
        if cur.strip():
            units.append(cur.strip())
        res = []
        for u in units:
            if len(u) <= 70:
                res.append(u)
                continue
            subparts = re.split(r"([，,；;])", u)
            buf = ""
            for sp in subparts:
                if re.match(r"[，,；;]", sp):
                    buf += sp
                    if buf.strip():
                        res.append(buf.strip())
                    buf = ""
                else:
                    if len(buf) + len(sp) > 70:
                        if buf.strip():
                            res.append(buf.strip())
                        buf = sp
                    else:
                        buf += sp
            if buf.strip():
                res.append(buf.strip())
        final = []
        acc = ""
        for piece in res:
            if len(piece) < 6:
                acc += piece + " "
                continue
            if acc:
                final.append(acc.strip())
                acc = ""
            final.append(piece)
        if acc.strip():
            final.append(acc.strip())
        return final

    async def _generate_and_broadcast_audio(self, text: str, api_key: str = None, base_url: str = None, voice: str = None):
        if not text:
            return

        clean_text = self._sanitize_text_for_tts(text)

        tts_api_key = api_key if api_key else settings.TTS_API_KEY
        tts_base_url = base_url if base_url else settings.TTS_BASE_URL
        # Use provided voice, or fallback to settings, or default
        tts_voice = voice if voice else (settings.TTS_VOICE if hasattr(settings, 'TTS_VOICE') else "sys_female_01")

        should_switch_to_settings = False
        if not tts_api_key:
            should_switch_to_settings = True
        elif tts_base_url and "deepseek" in tts_base_url.lower():
            should_switch_to_settings = True

        if should_switch_to_settings and settings.TTS_API_KEY:
            print(f"[Backend TTS] Switching to configured TTS provider (SiliconFlow) instead of {tts_base_url}")
            tts_api_key = settings.TTS_API_KEY
            tts_base_url = settings.TTS_BASE_URL or "https://api.siliconflow.cn/v1"

        if not tts_base_url:
            tts_base_url = "https://api.siliconflow.cn/v1"

        if not tts_api_key or len(str(tts_api_key).strip()) < 10:
            logger.error("[Backend TTS] Missing or invalid TTS API key. Provide X-SiliconFlow-Api-Key header or set TTS_API_KEY in .env")
            return

        try:
            print(f"[Backend TTS] Generating audio for text: {clean_text[:20]}... Voice: {tts_voice}")
            
            # Split into chunks for faster response
            chunks = self._split_into_chunks(clean_text)
            print(f"[Backend TTS] Split response into {len(chunks)} chunks.")
            
            tasks = []
            for sentence in chunks:
                if not sentence.strip(): continue
                tasks.append(
                    self.audio_service.generate_speech(
                        text=sentence,
                        api_key=tts_api_key,
                        base_url=tts_base_url,
                        model="FunAudioLLM/CosyVoice2-0.5B",
                        voice=tts_voice,
                        speed=1.0
                    )
                )
            
            if not tasks: return

            print(f"[Backend TTS] Starting {len(tasks)} TTS tasks concurrently...")
            
            # Schedule all tasks
            running_tasks = [asyncio.create_task(t) for t in tasks]
            
            for i, task in enumerate(running_tasks):
                try:
                    result = await task
                    if isinstance(result, bytes):
                        b64_audio = base64.b64encode(result).decode("utf-8")
                        await live2d_manager.broadcast({
                            "type": "cozy_audio",
                            "audioData": b64_audio,
                            "text": chunks[i] if i < len(chunks) else ""
                        })
                        print(f"[Backend TTS] Broadcasted chunk {i+1}/{len(chunks)}")
                        # Minimal delay to ensure network order
                        await asyncio.sleep(0.05)
                    else:
                        logger.error(f"[Backend TTS] Chunk {i} result invalid")
                except Exception as e:
                    logger.error(f"[Backend TTS] Error generating chunk {i}: {e}")

        except Exception as e:
            logger.error(f"[Backend TTS] Error generating audio: {e}")


    async def process_message(self, message: Union[str, List[Dict[str, Any]]], user_id: str, 
                            session_id: str = None,
                            target_api_key: str = None, 
                            target_base_url: str = None, 
                            target_model: str = None,
                            tts_api_key: str = None,
                            tts_base_url: str = None,
                            tts_voice: str = None,
                            enable_search: bool = False,
                            search_region: str = "zh-CN",
                            vision_config: Dict[str, Any] = None,
                            temperature: float = 0.7,
                            background_tasks: BackgroundTasks = None,
                            enable_backend_tts: bool = False,
                            enable_thinking: bool = False,
                            persona_mode: str = "full",
                            chat_mode: str = "persona",
                            deep_research: bool = False,
                            suppress_inner_monologue: bool = False,
                            user_nickname: Optional[str] = None) -> str:
        # 0. Update Person Stats
        self.person_service.increment_know_times(user_id)

        # Extract text content for analysis/storage if message is structured
        text_content = message
        if isinstance(message, list):
            text_content = ""
            for part in message:
                if part.get("type") == "text":
                    text_content += part.get("text", "") + "\n"
            text_content = text_content.strip()

        # 1. Save User Message
        with Session(engine) as session:
            user_msg = Conversation(role="user", content=text_content, session_id=session_id)
            session.add(user_msg)
            session.commit()

            # 2. Retrieve Context (Last 10 messages)
            # Filter by session_id if provided
            query = select(Conversation)
            if session_id:
                query = query.where(Conversation.session_id == session_id)
            
            statement = query.order_by(Conversation.id.desc()).limit(10)
            history = session.exec(statement).all()
            history.reverse() # Oldest first

        # 3. Gather Advanced Context (MaiBot Features)
        current_mood = "neutral"
        try:
            current_mood = self.mood_service.get_current_mood(user_id)
        except Exception as e:
            logger.warning(f"Mood retrieval failed, using default: {e}")

        react_context = ""
        try:
            react_context = await self.memory_system.retrieve_context(
                text_content, 
                user_id, 
                target_api_key, 
                target_base_url, 
                target_model
            )
        except Exception as e:
            logger.warning(f"Memory context retrieval failed, continuing without it: {e}")

        style_suggestion = ""
        try:
            style_suggestion = self.expression_service.get_style_suggestion(text_content)
        except Exception as e:
            logger.warning(f"Expression style retrieval failed, continuing without it: {e}")
        
        # 4. Build Prompt
        if persona_mode == "basic":
            system_prompt = FIREFLY_PERSONA_BASIC
        elif persona_mode == "advanced":
            system_prompt = FIREFLY_PERSONA_ADVANCED
        else:
            system_prompt = FIREFLY_PERSONA_FULL
        
        # Inject Current Time
        now_str = datetime.now().strftime("%Y年%m月%d日 %H:%M")
        system_prompt += f"\n\n[System Time]: 当前时间是 {now_str}。请时刻牢记这个时间点，对于任何关于时间的问题（如“今天是几号”、“现在是哪一年”），必须基于此时间回答，严禁产生幻觉或回答过去的时间。"

        system_prompt += f"\n\n[Current Mood]: {current_mood}"
        
        if react_context:
            system_prompt += f"\n\n[Thinking/Memory Context]:\n{react_context}"
        
        if style_suggestion:
            system_prompt += f"\n\n[Style Instruction]: {style_suggestion}"

        if user_nickname:
            system_prompt += f"\n\n[User Nickname]: 用户的昵称是：{user_nickname}。在称呼对方时请自然地使用这个昵称，不要使用“用户”等泛称。"

        # Output style rules based on chat mode
        if chat_mode == "persona" and not deep_research:
            system_prompt += """

[Output Style]:
- 在日常拟人聊天模式下，请使用纯文本回复。
- 不要使用 Markdown 格式（例如粗体 **文本**、列表符号 - 或标题 #）。
- 只有在用户明确要求使用 Markdown、或者需要展示代码片段 / 表格 / 结构化数据时，才可以使用 Markdown 或代码块。
"""
        if suppress_inner_monologue and not deep_research:
            system_prompt += """

[Inner Monologue Policy]:
- 严禁输出任何“心里描写/旁白/动作描写/OS”。
- 不要输出任何括号（() 或 （））包裹的舞台指令、动作或表情描述。
- 只输出对用户可见的正文内容。
"""

        # Inject Agent Instructions if enabled
        if enable_search:
             system_prompt += "\n\n" + AGENT_INSTRUCTIONS

        messages = [{"role": "system", "content": system_prompt}]
        
        for msg in history:
            messages.append({"role": msg.role, "content": msg.content})
        
        # Replace the last user message with the ORIGINAL structured message (containing image)
        if messages[-1]["role"] == "user":
             final_content = message
             messages[-1]["content"] = final_content

        # 5. ReAct Loop (Agent Mode)
        max_turns = 5
        current_turn = 0
        final_response_text = ""
        
        # If search is NOT enabled, we just do one pass (legacy mode)
        # But if enabled, we enter the loop.
        
        while current_turn < max_turns:
            try:
                response_data = await self.llm.get_response(messages, 
                                                          api_key=target_api_key, 
                                                          base_url=target_base_url, 
                                                          model=target_model,
                                                          temperature=temperature,
                                                          return_full=True,
                                                          enable_thinking=enable_thinking)
                
                reasoning_content = None
                native_tool_calls = None
                
                if isinstance(response_data, dict):
                    response_text = response_data.get("content", "")
                    reasoning_content = response_data.get("reasoning_content")
                    native_tool_calls = response_data.get("tool_calls")
                else:
                    response_text = response_data

                # Broadcast Thinking Process
                if reasoning_content:
                    print(f"[DeepSeek] Thinking: {reasoning_content[:50]}...")
                    await live2d_manager.broadcast({
                        "type": "gemini_response", # Reuse existing type
                        "text": "", # No text yet, just thinking
                        "reasoning_content": reasoning_content,
                        "isNewMessage": current_turn == 0 # Only new if first turn? Or handled by frontend?
                    })
                    
                    # Trigger Live2D Thinking Expression
                    # Only trigger periodically or on first chunk? 
                    # Since this is a full response from llm_service (non-streaming in this loop), 
                    # we get the whole thinking block at once.
                    await live2d_manager.broadcast({
                        "type": "expression",
                        "data": {
                            "mouth": 0.0,
                            "eyes": 1.0,
                            "eyebrow": 0.4,
                            "blush": 0.0,
                            "pupilX": 0.0,
                            "pupilY": 0.6, # Look up
                            "headTilt": 8.0
                        }
                    })
                
                # Broadcast Tool Calls (Native)
                if native_tool_calls:
                    print(f"[DeepSeek] Tool Calls: {len(native_tool_calls)}")
                    await live2d_manager.broadcast({
                        "type": "gemini_response",
                        "text": "",
                        "tool_calls": [t.model_dump() for t in native_tool_calls] if hasattr(native_tool_calls[0], 'model_dump') else native_tool_calls
                    })
                    
                    # Trigger Live2D Tool/Search Expression
                    await live2d_manager.broadcast({
                        "type": "expression",
                        "data": {
                            "mouth": 0.2,
                            "eyes": 1.0,
                            "eyebrow": 0.2,
                            "blush": 0.0,
                            "pupilX": 0.8, # Look side
                            "pupilY": 0.0,
                            "headTilt": -5.0
                        }
                    })

            except Exception as e:
                # Fallback for models that don't support vision/multimodal
                error_msg = str(e).lower()
                if "image_url" in error_msg or "400" in error_msg or "vision" in error_msg or "media" in error_msg:
                    print(f"Vision request failed ({e}). Checking for fallback...")
                    
                    # Check if Vision Agent is configured
                    if vision_config and vision_config.get("fallback") and vision_config.get("model"):
                        print("Vision Fallback Triggered: Using Secondary Agent")
                        
                        # Extract images from the last user message
                        last_msg = messages[-1]
                        images_to_analyze = []
                        if isinstance(last_msg["content"], list):
                            for part in last_msg["content"]:
                                if isinstance(part, dict) and part.get("type") == "image_url":
                                    url = part["image_url"].get("url")
                                    if url: images_to_analyze.append(url)
                        
                        if images_to_analyze:
                            # Analyze images
                            descriptions = await self._analyze_images_with_agent(images_to_analyze, vision_config)
                            
                            # Replace the message content with text + descriptions
                            # We keep the original text and append the image descriptions
                            original_text = ""
                            if isinstance(last_msg["content"], list):
                                for part in last_msg["content"]:
                                    if part.get("type") == "text":
                                        original_text += part.get("text", "") + "\n"
                            elif isinstance(last_msg["content"], str):
                                original_text = last_msg["content"]
                                
                            new_content = f"{original_text}\n\n[System: The user uploaded images, but your current model cannot see them. A vision agent has described them for you:]\n{descriptions}"
                            
                            messages[-1]["content"] = new_content
                            
                            # Retry the request with the new text-only message
                            response_text = await self.llm.get_response(messages, 
                                                                      api_key=target_api_key, 
                                                                      base_url=target_base_url, 
                                                                      model=target_model,
                                                                      temperature=temperature,
                                                                      enable_thinking=enable_thinking)
                        else:
                             # No images found to analyze, just retry as text
                             if messages[-1]["role"] == "user":
                                messages[-1]["content"] = text_content
                             response_text = await self.llm.get_response(messages, api_key=target_api_key, base_url=target_base_url, model=target_model, temperature=temperature, enable_thinking=enable_thinking)

                    else:
                        print("No Vision Agent configured. Downgrading to text-only.")
                        # Revert the last message to text-only
                        if messages[-1]["role"] == "user":
                            messages[-1]["content"] = text_content
                        
                        response_text = await self.llm.get_response(messages, 
                                                                  api_key=target_api_key, 
                                                                  base_url=target_base_url, 
                                                                  model=target_model,
                                                                  temperature=temperature,
                                                                  enable_thinking=enable_thinking)
                        response_text += "\n\n" + ("注：当前模型不支持视觉输入，已自动转为纯文本模式" if suppress_inner_monologue else "(注：当前模型不支持视觉输入，已自动转为纯文本模式)")
                else:
                    raise e

            # If Agent Mode is disabled, just return the response
            if not enable_search:
                final_response_text = response_text
                break

            # Check for Tool Call
            # Regex to match [TOOL_CALL] function_name(arg1="val", arg2="val")
            tool_call_match = re.search(r'\[TOOL_CALL\]\s+(\w+)\((.*?)\)', response_text, re.DOTALL)
            
            if tool_call_match:
                tool_name = tool_call_match.group(1)
                args_str = tool_call_match.group(2)
                
                print(f"[AGENT] Tool Call Detected: {tool_name}({args_str})")
                
                # Append Assistant Message (with Tool Call)
                messages.append({"role": "assistant", "content": response_text})
                
                # Execute Tool
                tool_result = await self._execute_tool(tool_name, args_str, search_region)
                
                # Append Tool Result as User Message (Standard ReAct pattern)
                messages.append({"role": "user", "content": f"[TOOL_RESULT]\n{tool_result}"})
                
                current_turn += 1
            else:
                # No tool call, this is the final answer
                # Validate images in the final response before returning
                if "[IMAGE:" in response_text:
                    print("[AGENT] Validating images in final response...")
                    final_response_text = await self.search_service._validate_images_in_output(response_text)
                else:
                    final_response_text = response_text
                break

        if suppress_inner_monologue:
            final_response_text = self._strip_inner_monologue_text(final_response_text)

        # 6. Save Assistant Response
        with Session(engine) as session:
            ai_msg = Conversation(role="assistant", content=final_response_text, session_id=session_id)
            session.add(ai_msg)
            session.commit()

        # 6.5 Meme Injection (Proactive)
        # Only in normal chat mode (not Deep Research), try to find a relevant meme
        if not deep_research:
            try:
                # Use the response text to find a meme
                memes = await self.meme_service.search_memes(final_response_text, limit=1, threshold=0.65, api_key=target_api_key, base_url=target_base_url)
                if memes:
                    meme = memes[0]
                    # Append meme to response. Frontend should handle [IMAGE: path] or similar tag
                    # Or we can send a separate event? For simplicity, we append to text.
                    # Assuming frontend handles standard Markdown image syntax or custom tag.
                    # Let's use a markdown image format.
                    # Note: path is relative or absolute. If absolute local path, frontend might not read it directly if web.
                    # Ideally backend serves it via static URL.
                    
                    # Assuming meme.path is stored relative to static/ or full path.
                    # If it's a full path in backend, we need to map it to a URL.
                    # For now, let's assume the path is serviceable or the frontend can handle it if it's local app.
                    # But the user said "backend responsible".
                    
                    # Construct a URL if possible, or just send the tag.
                    # Let's send a custom tag [MEME: <path>]
                    meme_tag = f"\n\n![Meme]({meme.path})"
                    final_response_text += meme_tag
                    self.meme_service.increment_usage(meme.id)
                    print(f"[ChatService] Injected meme: {meme.path}")
            except Exception as e:
                print(f"[ChatService] Meme injection failed: {e}")

        # 7. Post-Processing (Learning & Mood Update & Audio Generation)
        if background_tasks:
            background_tasks.add_task(self._learn_from_interaction, text_content, user_id, target_api_key, target_base_url, target_model)
            background_tasks.add_task(self.mood_service.update_mood, user_id, [{"role": "user", "content": text_content}, {"role": "assistant", "content": final_response_text}], target_api_key, target_base_url, target_model)
            if enable_backend_tts:
                final_tts_key = tts_api_key if tts_api_key else target_api_key
                final_tts_url = tts_base_url if tts_base_url else target_base_url
                tts_text = self._sanitize_text_for_tts(final_response_text)
                background_tasks.add_task(self._generate_and_broadcast_audio, tts_text, final_tts_key, final_tts_url, tts_voice)
        else:
            # Fallback for when no background_tasks context is provided
            # Note: Awaiting here will block the response, but it's safer than losing the tasks
            await self._learn_from_interaction(text_content, user_id, target_api_key, target_base_url, target_model)
            await self.mood_service.update_mood(
                user_id, 
                [{"role": "user", "content": text_content}, {"role": "assistant", "content": final_response_text}],
                target_api_key,
                target_base_url,
                target_model
            )
            if enable_backend_tts:
                final_tts_key = tts_api_key if tts_api_key else target_api_key
                final_tts_url = tts_base_url if tts_base_url else target_base_url
                tts_text = self._sanitize_text_for_tts(final_response_text)
                asyncio.create_task(self._generate_and_broadcast_audio(tts_text, final_tts_key, final_tts_url, tts_voice))

        return final_response_text

    async def _execute_tool(self, tool_name: str, args_str: str, region: str = "zh-CN") -> str:
        try:
            kwargs = self._parse_tool_kwargs(args_str)

            async def web_search_tool() -> str:
                query = kwargs.get("query")
                if not query:
                    return "Error: Missing 'query' argument."
                print(f"[AGENT] Executing web_search: {query}")
                return await self.search_service.search(query, region=region)

            async def visit_page_tool() -> str:
                url = kwargs.get("url")
                if not url:
                    return "Error: Missing 'url' argument."
                print(f"[AGENT] Executing visit_page: {url}")
                return await self.search_service.visit_page(url)

            async def academic_search_tool() -> str:
                query = kwargs.get("query")
                if not query:
                    return "Error: Missing 'query' argument."
                max_results_raw = kwargs.get("max_results")
                max_results = 5
                if max_results_raw:
                    try:
                        max_results = int(max_results_raw)
                    except Exception:
                        max_results = 5
                results = academic_search.search(query, max_results=max_results)
                return json.dumps(results, ensure_ascii=False)

            async def generate_ppt_tool() -> str:
                query = kwargs.get("query")
                filename = kwargs.get("filename")
                if not query:
                    return "Error: Missing 'query' argument."
                url = await self._skywork_generate_file_url("ppt", str(query))
                if not url:
                    return "Error: Skywork file generation unavailable."
                if not filename:
                    filename = f"slides_{int(datetime.now().timestamp())}.pptx"
                if not str(filename).lower().endswith(".pptx"):
                    filename = f"{filename}.pptx"
                path = await self._download_to_reports(url, str(filename))
                return json.dumps(
                    {
                        "status": "success",
                        "type": "PPTX",
                        "path": path,
                        "static_url": f"/static/reports/{Path(path).name}",
                    },
                    ensure_ascii=False,
                )

            async def generate_doc_tool() -> str:
                query = kwargs.get("query")
                filename = kwargs.get("filename")
                if not query:
                    return "Error: Missing 'query' argument."
                url = await self._skywork_generate_file_url("doc", str(query))
                if not url:
                    return "Error: Skywork file generation unavailable."
                if not filename:
                    filename = f"document_{int(datetime.now().timestamp())}.docx"
                if not str(filename).lower().endswith(".docx"):
                    filename = f"{filename}.docx"
                path = await self._download_to_reports(url, str(filename))
                return json.dumps(
                    {
                        "status": "success",
                        "type": "DOCX",
                        "path": path,
                        "static_url": f"/static/reports/{Path(path).name}",
                    },
                    ensure_ascii=False,
                )

            async def generate_sheet_tool() -> str:
                query = kwargs.get("query")
                filename = kwargs.get("filename")
                if not query:
                    return "Error: Missing 'query' argument."
                url = await self._skywork_generate_file_url("sheet", str(query))
                if not url:
                    return "Error: Skywork file generation unavailable."
                if not filename:
                    filename = f"sheet_{int(datetime.now().timestamp())}.xlsx"
                if not str(filename).lower().endswith(".xlsx"):
                    filename = f"{filename}.xlsx"
                path = await self._download_to_reports(url, str(filename))
                return json.dumps(
                    {
                        "status": "success",
                        "type": "XLSX",
                        "path": path,
                        "static_url": f"/static/reports/{Path(path).name}",
                    },
                    ensure_ascii=False,
                )

            tool_map = {
                "web_search": web_search_tool,
                "visit_page": visit_page_tool,
                "academic_search": academic_search_tool,
                "generate_ppt": generate_ppt_tool,
                "generate_doc": generate_doc_tool,
                "generate_sheet": generate_sheet_tool,
            }

            tool = tool_map.get(tool_name)
            if not tool:
                return f"Error: Unknown tool '{tool_name}'"
            return await tool()
                
        except Exception as e:
            logger.error(f"Tool execution failed: {e}")
            return f"Error executing tool: {str(e)}"

    async def _analyze_images_with_agent(self, images: List[str], config: Dict[str, Any]) -> str:
        """Uses a secondary vision model to describe images."""
        descriptions = []
        prompt = config.get("prompt") or "Describe this image in detail."
        
        # Limit to first 3 images to save tokens/time
        for i, img_url in enumerate(images[:3]):
            try:
                messages = [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": img_url}}
                        ]
                    }
                ]
                
                print(f"Vision Agent analyzing image {i+1}: {img_url}")
                desc = await self.llm.get_response(
                    messages,
                    api_key=config.get("api_key"),
                    base_url=config.get("base_url"),
                    model=config.get("model")
                )
                descriptions.append(f"Image {i+1} ({img_url}): {desc}")
            except Exception as e:
                print(f"Vision Agent failed on image {img_url}: {e}")
                descriptions.append(f"Image {i+1}: Analysis failed.")
        
        return "\n".join(descriptions)

    async def _learn_from_interaction(self, user_message: str, user_id: str, api_key: str = None, base_url: str = None, model: str = None):
        """Extracts facts and saves to memory."""
        analysis_json = await self.llm.analyze_text(user_message, MEMORY_EXTRACTION_PROMPT, api_key, base_url, model)
        try:
            # Clean up JSON markdown if present
            if "```json" in analysis_json:
                analysis_json = analysis_json.split("```json")[1].split("```")[0]
            
            data = json.loads(analysis_json)
            if data.get("should_save"):
                # Use PersonService to save memory linked to user
                await self.person_service.add_memory_point(
                    user_id=user_id,
                    content=data["memory_content"],
                    category=data.get("category", "other")
                )
                print(f"Learned new memory for {user_id}: {data['memory_content']}")
        except Exception as e:
            print(f"Learning failed: {e}")



