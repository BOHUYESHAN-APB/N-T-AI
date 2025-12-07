import json
from sqlmodel import Session, select
from app.models.database import engine, Conversation, Memory
from app.services.llm_service import LLMService
from app.services.person_service import PersonService
from app.services.mood_service import MoodService
from app.services.memory_system_service import MemorySystemService
from app.services.expression_service import ExpressionService
from app.services.search_service import SearchService
from app.core.prompts import FIREFLY_PERSONA, MEMORY_EXTRACTION_PROMPT, AGENT_INSTRUCTIONS
from app.core.logger import logger

from typing import Union, List, Dict, Any
import re
import ast
from datetime import datetime

class ChatService:
    def __init__(self):
        self.llm = LLMService()
        self.person_service = PersonService()
        self.mood_service = MoodService()
        self.memory_system = MemorySystemService()
        self.expression_service = ExpressionService()
        self.search_service = SearchService()

    async def process_message(self, message: Union[str, List[Dict[str, Any]]], user_id: str, 
                            session_id: str = None,
                            target_api_key: str = None, 
                            target_base_url: str = None, 
                            target_model: str = None,
                            enable_search: bool = False,
                            search_region: str = "zh-CN",
                            vision_config: Dict[str, Any] = None,
                            temperature: float = 0.7) -> str:
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
        current_mood = self.mood_service.get_current_mood(user_id)
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
        style_suggestion = self.expression_service.get_style_suggestion(text_content)
        
        # 4. Build Prompt
        system_prompt = FIREFLY_PERSONA
        
        # Inject Current Time
        now_str = datetime.now().strftime("%Y年%m月%d日 %H:%M")
        system_prompt += f"\n\n[System Time]: 当前时间是 {now_str}。请时刻牢记这个时间点，对于任何关于时间的问题（如“今天是几号”、“现在是哪一年”），必须基于此时间回答，严禁产生幻觉或回答过去的时间。"

        system_prompt += f"\n\n[Current Mood]: {current_mood}"
        
        if react_context:
            system_prompt += f"\n\n[Thinking/Memory Context]:\n{react_context}"
        
        if style_suggestion:
            system_prompt += f"\n\n[Style Instruction]: {style_suggestion}"

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
                response_text = await self.llm.get_response(messages, 
                                                          api_key=target_api_key, 
                                                          base_url=target_base_url, 
                                                          model=target_model,
                                                          temperature=temperature)
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
                                                                      temperature=temperature)
                        else:
                             # No images found to analyze, just retry as text
                             if messages[-1]["role"] == "user":
                                messages[-1]["content"] = text_content
                             response_text = await self.llm.get_response(messages, api_key=target_api_key, base_url=target_base_url, model=target_model, temperature=temperature)

                    else:
                        print("No Vision Agent configured. Downgrading to text-only.")
                        # Revert the last message to text-only
                        if messages[-1]["role"] == "user":
                            messages[-1]["content"] = text_content
                        
                        response_text = await self.llm.get_response(messages, 
                                                                  api_key=target_api_key, 
                                                                  base_url=target_base_url, 
                                                                  model=target_model,
                                                                  temperature=temperature)
                        response_text += "\n\n(注：当前模型不支持视觉输入，已自动转为纯文本模式)"
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

        # 6. Save Assistant Response
        with Session(engine) as session:
            ai_msg = Conversation(role="assistant", content=final_response_text, session_id=session_id)
            session.add(ai_msg)
            session.commit()

        # 7. Post-Processing (Learning & Mood Update)
        await self._learn_from_interaction(text_content, user_id, target_api_key, target_base_url, target_model)
        await self.mood_service.update_mood(
            user_id, 
            [{"role": "user", "content": text_content}, {"role": "assistant", "content": final_response_text}],
            target_api_key,
            target_base_url,
            target_model
        )

        return final_response_text

    async def _execute_tool(self, tool_name: str, args_str: str, region: str = "zh-CN") -> str:
        try:
            # Simple argument parsing
            # We wrap it in a function call syntax to use ast.parse if needed, 
            # or just regex extract. 
            # Let's try to parse the args_str as keyword arguments.
            
            kwargs = {}
            # Regex to find key="value" or key='value'
            # This is a simple parser, might need to be more robust for complex args
            matches = re.findall(r'(\w+)=["\'](.*?)["\']', args_str)
            for key, value in matches:
                kwargs[key] = value
            
            if tool_name == "web_search":
                query = kwargs.get("query")
                if not query: return "Error: Missing 'query' argument."
                print(f"[AGENT] Executing web_search: {query}")
                return await self.search_service.search(query, region=region)
            
            elif tool_name == "visit_page":
                url = kwargs.get("url")
                if not url: return "Error: Missing 'url' argument."
                print(f"[AGENT] Executing visit_page: {url}")
                return await self.search_service.visit_page(url)
            
            else:
                return f"Error: Unknown tool '{tool_name}'"
                
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
