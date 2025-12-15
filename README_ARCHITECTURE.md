# Project Architecture & Logic Flow

## Overview
This project consists of three main components working together to create an interactive AI virtual character system.

### 1. Frontend (Flutter Application)
**Path:** `/flutter_application`
- **Role:** The main user interface and control center.
- **Responsibilities:**
  - Displays the Chat Interface (bubbles, history, etc.).
  - Handles user input (Text, Voice).
  - **CRITICAL: Performs TTS (Text-to-Speech) and STT (Speech-to-Text) locally/directly.**
    - *Note:* Audio generation must happen here to ensure proper Live2D Lip-Sync timing. Do not offload this to the backend for the main character.
  - Manages Settings (API Keys, Model Selection, Thinking Mode Toggle).
  - Embeds the Live2D Renderer (via WebView) or communicates with it.
  - Displays Danmaku and Super Chat messages (via Plugin integration).
- **Communication:** Sends HTTP requests to the Backend (`/v1/chat/completions`) with configuration headers (e.g., `X-Enable-Thinking`).

### 2. Backend (FastAPI Server)
**Path:** `/backend`
- **Role:** The brain and bridge of the system.
- **Responsibilities:**
  - **LLM Service:** Handles interactions with LLMs (DeepSeek, Gemini, etc.), including "Thinking Mode" and Tool Calls.
  - **Plugin System:** Manages external integrations like Bilibili Live (Danmaku/SC).
  - **Live2D Routes:** Serves the static files for the renderer and manages WebSocket connections for real-time control.
  - **Chat Service:** Processes messages, updates memory/mood, and broadcasts events to the Live2D renderer.
- **Data Flow:**
  - Receives Chat/Action requests from Flutter.
  - Processes logic (LLM, Plugins).
  - Broadcasts visual/audio commands to the Live2D Renderer via WebSocket.

### 3. Live2D Renderer (Web/HTML)
**Path:** `/backend/app/static/live2d`
- **Role:** The visual presentation layer.
- **Responsibilities:**
  - Renders the Live2D model (Cubism SDK).
  - Plays animations (Motions) and Expressions based on backend commands.
  - Performs Lip-Sync (Audio visualization).
  - **Note:** This is a *display-only* component. It should NOT contain control logic (checkboxes, inputs) or main chat history, unless used as a standalone Stream Overlay (OBS).
- **Communication:** Connects to Backend via WebSocket (`/api/live2d/ws`) to receive `expression`, `motion`, and `audio` events.

---

## Message Types & Display Logic

The system distinguishes between different message sources to allow the Frontend (Flutter) to render them appropriately:

1.  **User Message (`user`)**: Direct input from the user (Text/Voice).
    - *Display:* Right side, distinctive bubble.
2.  **AI Message (`gemini` / `ai`)**: The character's response.
    - *Display:* Left side, character avatar.
    - *Features:* Can include "Thinking Process" (expandable) and "Tool Calls".
3.  **Chat Normal (`chat_normal`)**: Danmaku/Comments from live stream (via Plugin).
    - *Display:* Middle area, smaller/translucent bubbles.
4.  **Super Chat (`chat_sc`)**: Paid/Highlighted messages from live stream.
    - *Display:* Middle area, prominent Gold/Color styling.
5.  **Agent/System (`agent` / `system`)**: Internal system messages or other agent outputs.
    - *Display:* Distinct style or system notification area.

## DeepSeek Thinking Mode Configuration

To enable the DeepSeek "Thinking Mode" (Chain of Thought), the Frontend (Flutter) must send the following header in the API request:

- **Header:** `X-Enable-Thinking: true`
- **Backend Logic:**
  - If `target_model` is `deepseek-chat` AND header is `true` -> Enable `thinking` parameter.
  - If `target_model` is `deepseek-reasoner` -> Thinking is FORCED by default (header ignored).
  - Other models -> Header ignored.
