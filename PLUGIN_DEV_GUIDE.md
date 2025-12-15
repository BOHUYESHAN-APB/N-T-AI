PS D:\-Users-\Documents\GitHub\N-T-AI\backend> python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000                   
INFO:     Will watch for changes in these directories: ['D:\\-Users-\\Documents\\GitHub\\N-T-AI\\backend']
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Started reloader process [42124] using WatchFiles
D:\-Users-\Documents\GitHub\N-T-AI\backend\app\services\search_service.py:12: RuntimeWarning: This package (`duckduckgo_search`) has been renamed to `ddgs`! Use `pip install ddgs` instead.
  self.ddgs = DDGS()
D:\-Users-\Documents\GitHub\N-T-AI\backend\app\services\search_service.py:12: RuntimeWarning: This package (`duckduckgo_search`) has been renamed to `ddgs`! Use `pip install ddgs` instead.       
  self.ddgs = DDGS()
INFO:     Started server process [40184]
INFO:     Waiting for application startup.
2025-12-15 15:10:24,915 - astra_me - INFO - Starting up Astra-Me Backend...
2025-12-15 15:10:24,918 INFO sqlalchemy.engine.Engine BEGIN (implicit)
2025-12-15 15:10:24,919 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("memory")
2025-12-15 15:10:24,919 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,921 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("conversation")
2025-12-15 15:10:24,922 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,923 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("person")
2025-12-15 15:10:24,923 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,924 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("memorypoint")
2025-12-15 15:10:24,924 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,925 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("jargon")
2025-12-15 15:10:24,925 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,926 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("expressionstyle")
2025-12-15 15:10:24,926 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,927 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("thinkingback")
2025-12-15 15:10:24,928 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,929 INFO sqlalchemy.engine.Engine PRAGMA main.table_info("moodstate")
2025-12-15 15:10:24,930 INFO sqlalchemy.engine.Engine [raw sql] ()
2025-12-15 15:10:24,931 INFO sqlalchemy.engine.Engine COMMIT     
[bilibili_live] Plugin started.
[bilibili_live] Plugin startup, initializing blivedm client...   
[bilibili_live] Invalid or missing room_id
INFO:     Application startup complete.
INFO:     127.0.0.1:50164 - "GET /static/live2d/index.html HTTP/1.1" 200 OK
INFO:     127.0.0.1:57136 - "GET /static/live2d/index.html?model=/static/live2d/mao_pro_zh/mao_pro_zh/runtime/mao_pro.model3.json&debug=false&floating=true&controls=true HTTP/1.1" 304 Not Modified
INFO:     127.0.0.1:57136 - "GET /static/live2d/audio-loader.js HTTP/1.1" 304 Not Modified
INFO:     127.0.0.1:11129 - "GET /static/live2d/live2d.v2.js HTTP/1.1" 304 Not Modified
INFO:     127.0.0.1:57136 - "GET /static/live2d/app.js HTTP/1.1" 304 Not Modified
INFO:     127.0.0.1:57136 - "GET /favicon.ico HTTP/1.1" 404 Not Found
INFO:     127.0.0.1:57136 - "GET /api/live2d/emotion_mapping/mao_pro_zh HTTP/1.1" 404 Not Found
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\websockets\legacy\server.py:1178: DeprecationWarning: remove second argument of ws_handler
  warnings.warn("remove second argument of ws_handler", DeprecationWarning)
INFO:     127.0.0.1:43722 - "WebSocket /api/live2d/ws" [accepted]
[Live2D WS] Client connected. Total: 1
INFO:     connection open
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\websockets\legacy\server.py:1178: DeprecationWarning: remove second argument of ws_handler
  warnings.warn("remove second argument of ws_handler", DeprecationWarning)
INFO:     127.0.0.1:44574 - "WebSocket /api/live2d/ws" [accepted]
[Live2D WS] Client connected. Total: 2
INFO:     connection open
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\websockets\legacy\server.py:1178: DeprecationWarning: remove second argument of ws_handler
  warnings.warn("remove second argument of ws_handler", DeprecationWarning)
INFO:     127.0.0.1:8106 - "WebSocket /api/live2d/ws" [accepted] 
[Live2D WS] Client connected. Total: 3
INFO:     connection open
INFO:     127.0.0.1:52008 - "GET /static/bilibili/bilibili_danmaku.html?mode=danmaku&theme=default HTTP/1.1" 304 Not Modified     
INFO:     127.0.0.1:52008 - "GET /static/bilibili/bili_emoji.json HTTP/1.1" 200 OK
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\websockets\legacy\server.py:1178: DeprecationWarning: remove second argument of ws_handler
  warnings.warn("remove second argument of ws_handler", DeprecationWarning)
INFO:     127.0.0.1:55668 - "WebSocket /api/v1/plugins/bilibili_live/stream" [accepted]
INFO:     connection open
INFO:     127.0.0.1:2281 - "POST /api/v1/plugins/bilibili_live/config HTTP/1.1" 200 OK
[bilibili_live] Connecting to room 10699540 using blivedm...
D:\-Users-\Documents\GitHub\N-T-AI\backend\app\plugins\bilibili_live\blivedm\clients\ws_base.py:101: DeprecationWarning: client.loop property is deprecated
  assert self._session.loop is asyncio.get_event_loop()  # noqa  
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\aiohttp\client.py:1488: DeprecationWarning: float parameter 'receive_timeout' is deprecated, please use parameter 'timeout=ClientWSTimeout(ws_receive=...)'
  self._resp: _RetType = await self._coro
room=10699540 unknown cmd=LOG_IN_NOTICE, command={'cmd': 'LOG_IN_NOTICE', 'data': {'notice_msg': '为保护用户隐私，未登录无法查看他人昵称', 'image_web': 'http://i0.hdslb.com/bfs/dm/75e7c16b99208df259fe0a93354fd3440cbab412.png', 'image_app': 'http://i0.hdslb.com/bfs/dm/b632f7dcd3acf47deffb5f9ccc9546ae97a3415b.png'}}
room=10699540 unknown cmd=WATCHED_CHANGE, command={'cmd': 'WATCHED_CHANGE', 'data': {'num': 0, 'text_small': '0', 'text_large': '0人看过'}}
room=10699540 unknown cmd=ONLINE_RANK_V3, command={'cmd': 'ONLINE_RANK_V3', 'data': {'pb': 'CgtvbmxpbmVfcmFuaxqSAwjVyOqWARJKaHR0cHM6Ly9pMi5oZHNsYi5jb20vYmZzL2ZhY2UvZjdkOTM2NzllODRiMmExMzgzYWJlZDYxOWZkOTc2OWEwNjE4ZGFkOC5qcGcaATIiDOafj+S5juWknOWxsSgBQqoCCNXI6pYBEp8CCgzmn4/kuY7lpJzlsbESSmh0dHBzOi8vaTIuaGRzbGIuY29tL2Jmcy9mYWNlL2Y3ZDkzNjc5ZTg0YjJhMTM4M2FiZWQ2MTlmZDk3NjlhMDYxOGRhZDguanBnKloKDOafj+S5juWknOWxsRJKaHR0cHM6Ly9pMi5oZHNsYi5jb20vYmZzL2ZhY2UvZjdkOTM2NzllODRiMmExMzgzYWJlZDYxOWZkOTc2OWEwNjE4ZGFkOC5qcGcyWgoM5p+P5LmO5aSc5bGxEkpodHRwczovL2kyLmhkc2xiLmNvbS9iZnMvZmFjZS9mN2Q5MzY3OWU4NGIyYTEzODNhYmVkNjE5ZmQ5NzY5YTA2MThkYWQ4LmpwZzoLIP///////////wEyAA=='}}
[bilibili_live] Danmaku from 柏***: 测试
[bilibili_live] Sending danmaku summary to Main Brain...
2025-12-15 15:12:32,216 INFO sqlalchemy.engine.Engine BEGIN (implicit)
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\asyncio\selector_events.py:879: ResourceWarning: unclosed transport <_SelectorSocketTransport fd=1608 read=idle write=<idle, bufsize=0>>
  _warn(f"unclosed transport {self!r}", ResourceWarning, source=self)
ResourceWarning: Enable tracemalloc to get the object allocation traceback
2025-12-15 15:12:32,335 INFO sqlalchemy.engine.Engine SELECT person.id, person.user_id, person.nickname, person.know_times, person.created_at
FROM person
WHERE person.user_id = ?
2025-12-15 15:12:32,335 INFO sqlalchemy.engine.Engine [generated in 0.00053s] ('bilibili_agent',)
2025-12-15 15:12:32,336 INFO sqlalchemy.engine.Engine ROLLBACK   
C:\Users\BoHuYeShan\AppData\Local\Programs\Python\Python312\Lib\site-packages\pydantic\fields.py:656: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  return fac()
2025-12-15 15:12:32,339 INFO sqlalchemy.engine.Engine BEGIN (implicit)
2025-12-15 15:12:32,341 INFO sqlalchemy.engine.Engine INSERT INTO conversation (session_id, role, content, timestamp) VALUES (?, ?, ?, ?)
2025-12-15 15:12:32,341 INFO sqlalchemy.engine.Engine [generated in 0.00041s] (None, 'user', 'Current Danmaku Summary: 【弹幕总结 】  \n- **关键话题**：暂无明确讨论主题，仅出现一条测试性弹幕。  \n- **整体情绪**：中性（测试消息无情绪倾向）。  \n- **需注意点**：观众“柏***”发送了测试弹幕，可能为检查连接或互动功能，建议主播简单确认互动正常即可。. Please allow the main brain to understand the current audience atmosphere. If there are questions or interactions, please respond briefly.', '2025-12-15 07:12:32.338339')     
2025-12-15 15:12:32,347 INFO sqlalchemy.engine.Engine COMMIT
2025-12-15 15:12:32,360 INFO sqlalchemy.engine.Engine BEGIN (implicit)
2025-12-15 15:12:32,362 INFO sqlalchemy.engine.Engine SELECT conversation.id, conversation.session_id, conversation.role, conversation.content, conversation.timestamp
FROM conversation ORDER BY conversation.id DESC
 LIMIT ? OFFSET ?
2025-12-15 15:12:32,362 INFO sqlalchemy.engine.Engine [generated in 0.00093s] (10, 0)
2025-12-15 15:12:32,364 INFO sqlalchemy.engine.Engine ROLLBACK   
2025-12-15 15:12:32,365 INFO sqlalchemy.engine.Engine BEGIN (implicit)
2025-12-15 15:12:32,367 INFO sqlalchemy.engine.Engine SELECT moodstate.id, moodstate.user_id, moodstate.current_mood, moodstate.last_updated
FROM moodstate
WHERE moodstate.user_id = ?
2025-12-15 15:12:32,367 INFO sqlalchemy.engine.Engine [generated in 0.00028s] ('bilibili_agent',)
2025-12-15 15:12:32,368 INFO sqlalchemy.engine.Engine ROLLBACK   
-----
1765782628013 [stdout] flutter: [Live2DBroadcast] Enabled: true
1765782628015 [stdout] flutter: [Live2DBroadcast] Enabled: true
1765782630071 [stdout] flutter: [FloatingWindowWindows] WebView window created with URL: http://localhost:8000/static/live2d/index.html?model=/static/live2d/mao_pro_zh/mao_pro_zh/runtime/mao_pro.model3.json&debug=false&floating=true&controls=true
1765782640320 [stdout] flutter: [Bilibili Live] Plugin enabled
1765782639049 [flutter.navigation] {
  "type": "Event",
  "kind": "Extension",
  "extensionKind": "Flutter.Navigation",
  "isolateGroup": {
    "type": "@IsolateGroup",
    "id": "isolateGroups/5594266219868861",
    "name": "main.dart",
    "number": "5594266219868861",
    "isSystemIsolateGroup": false
  },
  "isolate": {
    "type": "@Isolate",
    "id": "isolates/4660710455121287",
    "name": "main",
    "number": "4660710455121287",
    "isSystemIsolate": false,
    "isolateGroupId": "isolateGroups/5594266219868861"
  },
  "timestamp": 1765782639049,
  "extensionData": {
    "route": {
      "description": "MaterialPageRoute<dynamic>(null)",
      "settings": {
        "name": null
      }
    }
  }
}
1765782707796 [flutter.navigation] {
  "type": "Event",
  "kind": "Extension",
  "extensionKind": "Flutter.Navigation",
  "isolateGroup": {
    "type": "@IsolateGroup",
    "id": "isolateGroups/5594266219868861",
    "name": "main.dart",
    "number": "5594266219868861",
    "isSystemIsolateGroup": false
  },
  "isolate": {
    "type": "@Isolate",
    "id": "isolates/4660710455121287",
    "name": "main",
    "number": "4660710455121287",
    "isSystemIsolate": false,
    "isolateGroupId": "isolateGroups/5594266219868861"
  },
  "timestamp": 1765782707796,
  "extensionData": {
    "route": {
      "description": "MaterialPageRoute<dynamic>(null)",
      "settings": {
        "name": null
      }
    }
  }
}
