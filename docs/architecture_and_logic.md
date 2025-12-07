# N-T-AI 系统架构与前后端交互逻辑说明

本文档详细说明了 N-T-AI 项目中 Flutter 前端与 Python 后端之间的交互逻辑，特别是关于配置传递、API 调用代理以及 Agent 模式的实现细节。旨在确保后续开发维护（包括 AI 辅助开发）时能准确理解系统行为。

## 1. 系统运行模式

系统支持两种主要的运行模式，由前端设置中的 `Enable Python Backend` (开启后端) 选项控制：

### 1.1 前端直连模式 (Direct Mode)
*   **描述**: Flutter 前端直接调用 LLM 提供商的 API（如 OpenAI, DeepSeek, Aliyun 等）。
*   **适用场景**: 简单的对话，不需要本地知识库、记忆系统或复杂 Agent 工具调用的场景。
*   **逻辑**:
    *   前端读取 `settings.ai.providers` 中的配置。
    *   直接向 `provider.baseUrl` 发起 HTTP 请求。
    *   **注意**: 此模式下无法使用 Python 后端的记忆系统、情感分析和搜索工具。

### 1.2 后端代理模式 (Backend Proxy Mode)
*   **描述**: Flutter 前端将用户的输入和**当前的 AI 配置**发送给本地 Python 后端 (`localhost:8000`)，由后端代理执行实际的 LLM 调用。
*   **适用场景**: 需要使用记忆系统 (Memory)、情感分析 (Mood)、联网搜索 (Web Search) 或视觉代理 (Vision Agent) 的场景。
*   **核心逻辑**: 后端作为一个无状态（或弱状态）的执行器，它使用**前端传递过来的配置**来实例化 LLM 客户端。这意味着后端不需要在 `.env` 中配置所有的 Key，而是动态使用前端选中的配置。

## 2. 前后端交互协议 (关键)

在 **后端代理模式** 下，前端 (`lib/core/services/llm_service.dart`) 必须通过 HTTP Headers 将配置传递给后端。

### 2.1 请求头定义 (Headers)

前端发送给后端 (`/v1/chat/completions` 或 `/v1/embeddings`) 的请求中包含以下关键 Header：

| Header 字段 | 说明 | 逻辑处理 |
| :--- | :--- | :--- |
| `X-Target-Api-Key` | 目标 LLM 的 API Key | 后端读取此 Key 初始化 OpenAI Client。 |
| `X-Target-Base-Url` | 目标 LLM 的 Base URL | **重要**: 前端必须进行清洗，移除末尾的 `/chat/completions`，确保传递的是标准的 Base URL (如 `https://api.example.com/v1`)。 |
| `X-Target-Model` | 目标模型名称 | 如 `gpt-4`, `deepseek-chat` 等。 |
| `X-Enable-Browser` | 是否开启联网/Agent | `"true"` 或 `"false"`。控制后端是否进入 ReAct Agent 循环。 |
| `X-Search-Region` | 搜索区域 | 如 `zh-CN` 或 `wt-wt`。 |
| `X-Usage-Type` | 用途类型 | `main` (主对话), `memory` (记忆提取), `system` (系统任务)。用于后端区分是否更新情感值。 |

### 2.2 视觉代理配置 (Vision Agent Headers)

当主模型不支持视觉（如 DeepSeek-V3），但用户发送了图片时，前端会额外传递视觉模型的配置，供后端在 Fallback 逻辑中使用：

| Header 字段 | 说明 |
| :--- | :--- |
| `X-Vision-Api-Key` | 视觉模型的 API Key |
| `X-Vision-Base-Url` | 视觉模型的 Base URL (同样需要清洗) |
| `X-Vision-Model` | 视觉模型名称 (如 `gpt-4o`, `qwen-vl-max`) |
| `X-Vision-Prompt` | 视觉识别提示词 (URL Encoded) |
| `X-Vision-Fallback` | 是否允许自动回退 |

## 3. 关键代码逻辑实现

### 3.1 前端逻辑 (`lib/core/services/llm_service.dart`)

在调用后端之前，必须执行 URL 清洗：

```dart
// 伪代码示例
if (enablePythonBackend) {
  requestUrl = '$backendUrl/v1/chat/completions';
  
  headers['X-Target-Api-Key'] = provider.apiKey;
  
  // URL 清洗逻辑：确保不包含具体的 endpoint 路径
  var targetBaseUrl = provider.baseUrl;
  if (targetBaseUrl.endsWith('/chat/completions')) {
    targetBaseUrl = targetBaseUrl.replaceAll('/chat/completions', '');
  }
  if (targetBaseUrl.endsWith('/')) {
    targetBaseUrl = targetBaseUrl.substring(0, targetBaseUrl.length - 1);
  }
  headers['X-Target-Base-Url'] = targetBaseUrl;
  // ... 其他 headers
}
```

### 3.2 后端逻辑 (`backend/main.py` & `app/services/chat_service.py`)

后端接收请求后，动态构建 Client：

```python
# main.py
target_api_key = raw_request.headers.get("X-Target-Api-Key")
target_base_url = raw_request.headers.get("X-Target-Base-Url")
# ...

# chat_service.py -> llm_service.py
async def get_response(..., api_key, base_url, model):
    # 优先使用传入的 api_key 和 base_url，而非环境变量
    if api_key and base_url:
        client = openai.AsyncOpenAI(api_key=api_key, base_url=base_url)
    else:
        client = self.default_client
    # ...
```

## 4. 维护注意事项

1.  **不要在后端硬编码 Key**: 除非是用于系统内部的默认 fallback，否则应始终优先使用 `X-Target-*` 传递的参数。
2.  **URL 格式一致性**: 不同的 LLM 提供商对 Base URL 的定义不同（有的带 `/v1` 有的不带）。前端的清洗逻辑应尽可能兼容，后端则应直接使用清洗后的 URL。
3.  **新增参数**: 如果需要传递新的配置（如 `temperature` 或 `top_p`），请遵循 `X-Target-*` 的命名规范在 Header 中添加，并在后端 `main.py` 中解析。

---
*文档更新日期: 2025-12-04*
