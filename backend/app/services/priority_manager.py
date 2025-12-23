import asyncio
import time
import random
from typing import Dict, Any, Optional, List, Union
from app.core.logger import logger
from app.services.search_service import SearchService
from app.core.config import settings

class ChatPriority:
    USER = 1        # 最高优先级 (Microphone/Text)
    VOICE_CH = 2    # 中等优先级 (Voice Channel Loopback)
    BARRAGE = 3     # 最低优先级 (Plugin/Barrage)
    PROACTIVE = 4   # 主动触发 (Heartbeat/Idle)

class PriorityTask:
    def __init__(self, priority: int, message: Union[str, List[Dict[str, Any]]], user_id: str, **kwargs):
        self.priority = priority
        self.message = message
        self.user_id = user_id
        self.kwargs = kwargs
        self.timestamp = time.time()
        self.id = f"{priority}_{self.timestamp}_{random.randint(0, 1000)}"

class PriorityManager:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(PriorityManager, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.queue = asyncio.PriorityQueue()
        self.current_task: Optional[asyncio.Task] = None
        from app.services.chat_service import ChatService
        self.chat_service = ChatService()
        self.search_service = SearchService()
        self.last_activity_ts = time.time()
        self.proactive_chat_enabled = False # 默认关闭
        self.is_running = False
        self._initialized = True

    async def start(self):
        if self.is_running:
            return
        self.is_running = True
        asyncio.create_task(self._worker())
        asyncio.create_task(self._heartbeat_loop())
        logger.info("PriorityManager started.")

    async def add_task(self, priority: int, message: Union[str, List[Dict[str, Any]]], user_id: str, **kwargs):
        """添加一个带优先级的任务"""
        # 如果是用户输入，更新最后活动时间
        if priority == ChatPriority.USER:
            self.last_activity_ts = time.time()
            
        task = PriorityTask(priority, message, user_id, **kwargs)
        # PriorityQueue uses (priority, timestamp, task) for sorting
        # Lower priority value means higher priority in asyncio.PriorityQueue
        await self.queue.put((priority, task.timestamp, task))
        logger.info(f"Task added to queue: priority={priority}, id={task.id}")

    def set_proactive_chat(self, enabled: bool):
        """设置主动搭话开关"""
        self.proactive_chat_enabled = enabled
        if enabled:
            self.last_activity_ts = time.time() # 重置计时
        logger.info(f"Proactive chat {'enabled' if enabled else 'disabled'}")

    async def _worker(self):
        while self.is_running:
            try:
                # Get next task from queue
                prio, ts, task = await self.queue.get()
                
                # If there's a higher priority task in queue, we might want to skip lower ones
                # but for now, we just process one by one to avoid starvation
                
                logger.info(f"Processing task: priority={task.priority}, id={task.id}")
                
                # Check if this task is still relevant (optional: e.g. skip if too old)
                
                # Execute chat service
                try:
                    # 确保 kwargs 中包含 tts_mode，如果不存在则默认为 "sentence"
                    kwargs = task.kwargs.copy()
                    if "tts_mode" not in kwargs:
                        kwargs["tts_mode"] = "sentence"
                        
                    await self.chat_service.process_message(
                        message=task.message,
                        user_id=task.user_id,
                        **kwargs
                    )
                except Exception as e:
                    logger.error(f"Error processing message in PriorityManager: {e}")
                
                self.queue.task_done()
                
            except Exception as e:
                logger.error(f"PriorityManager worker error: {e}")
                await asyncio.sleep(1)

    async def _heartbeat_loop(self):
        """心跳循环，处理空闲主动搭话"""
        while self.is_running:
            try:
                # 必须开启主动搭话开关才执行
                if not self.proactive_chat_enabled:
                    await asyncio.sleep(10)
                    continue

                # 检查空闲时间
                idle_sec = time.time() - self.last_activity_ts
                idle_limit = float(getattr(settings, "PROACTIVE_IDLE_MIN_SEC", 45) or 45)
                
                if idle_sec >= idle_limit:
                    # 触发主动搭话
                    if self.queue.empty():
                        await self._trigger_proactive_chat()
                        # 更新时间以避免连续触发
                        self.last_activity_ts = time.time()
                
                # 心跳间隔
                await asyncio.sleep(10)
            except Exception as e:
                logger.error(f"Heartbeat loop error: {e}")
                await asyncio.sleep(10)

    async def _trigger_proactive_chat(self):
        """触发主动搭话，有概率使用搜索"""
        logger.info("Triggering proactive chat...")
        
        # 30% 概率触发搜索增强的搭话
        if random.random() < 0.3:
            try:
                # 随便搜点热门话题或新闻
                topics = ["科技新闻", "有趣的冷知识", "今天的热门话题", "AI 进展", "最近的动漫资讯", "最新的游戏动态"]
                topic = random.choice(topics)
                search_res = await self.search_service.search(topic, max_results=3)
                
                # 构建系统提示词
                prompt = f"""[System Notification]: 现在是空闲时间，你主动搜索到了关于'{topic}'的信息。请你根据这些信息，主动跟用户聊个天。
                
这是搜索结果：
{search_res}

要求：
1. 保持高度口语化，不要像个机器人，要有你的性格特色（如：有点小傲娇、温柔、或者带点幽默感）。
2. 提到这个话题，但不要说你是“搜索”到的，可以说“刚才偶然看到”、“听别人说”或者“突然想到”。
3. 结尾顺便抛出一个相关的小问题，引导用户和你互动。
4. 回复要短小精悍，不要超过3句话。
"""
                await self.add_task(ChatPriority.PROACTIVE, prompt, "heartbeat_user", enable_backend_tts=True)
                return
            except Exception as e:
                logger.warning(f"Proactive search failed: {e}")
        
        # 默认主动搭话
        default_prompts = [
            "空闲时请你主动说一句话，口语化一点，短一些，可以带点口癖，并顺便抛一个轻问题。",
            "你现在有点无聊，主动找用户搭个话，分享一个你此时的‘心情’或者想做的事，并问问他在干嘛。",
            "你突然想到了一个很有趣的问题，主动问问用户的看法。保持口语化和个性。",
            "你观察到用户已经有一阵子没说话了，主动问候一下，或者说句俏皮话。"
        ]
        prompt = random.choice(default_prompts)
        await self.add_task(ChatPriority.PROACTIVE, prompt, "heartbeat_user", enable_backend_tts=True)

priority_manager = PriorityManager()
