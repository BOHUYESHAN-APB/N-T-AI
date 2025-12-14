# N-T-AI (Nexus-Thinking AI)

![N-T-AI Banner](flutter_application/assets/images/banner.png)

<div align="center">

[![Version](https://img.shields.io/badge/Version-0.3.3%20Beta-blue)](https://github.com/BOHUYESHAN-APB/N-T-AI)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20macOS-lightgrey)](https://flutter.dev)
[![Sponsor](https://img.shields.io/badge/Sponsor-Afdian-pink)](https://afdian.com/a/N-T-AI)
[![SiliconFlow](https://img.shields.io/badge/SiliconFlow-Referral-purple)](https://cloud.siliconflow.cn/i/oiWI8xjZ)

</div>

**N-T-AI** is a cross-platform AI assistant application built with Flutter, designed to provide a highly customizable, emotionally interactive, and autonomous AI companion experience. It combines a beautiful, interactive frontend with a powerful, logic-driven backend to create a digital entity that doesn't just chat, but "lives" on your device.

For the Chinese version of the documentation, see: [中文文档](docs/README_zh-CN.md)

---

## 💖 Support & Sponsorship

If you find this project helpful, please consider supporting us:

*   **[Sponsor on Afdian (爱发电)](https://afdian.com/a/N-T-AI)**: Support our development directly.
*   **[Register on SiliconFlow](https://cloud.siliconflow.cn/i/oiWI8xjZ)**: Use our referral link to get 20M free tokens and support us with compute credits.

---

## 📖 Table of Contents
- [Core Features](#-core-features)
- [Architecture & Design](#-architecture--design)
- [Deployment & Installation](#-deployment--installation)
- [Configuration & Security](#-configuration--security)
- [Roadmap](#-roadmap)
- [Development](#-development)
- [License](#-license)

---

## 🚀 Core Features

### 1. Multimodal & Emotional Engine
*   **Expression Agent**: Real-time emotional inference engine that displays dynamic expressions (Dynamic Island style) based on conversation context.
*   **Live2D Integration**: Full support for Live2D models with motion tracking, emotional feedback loops, and smooth animation transitions.
*   **Vision Capabilities**: 
    *   **Direct Input**: Support for multimodal interactions using GPT-4o, Claude 3.5 Sonnet, Qwen-VL, etc.
    *   **Vision Fallback Agent**: Automatically delegates image understanding to a specialized Vision Agent if the primary model lacks vision support.

### 2. Autonomous Agent System (ReAct)
*   **Web Search & Browsing**: The system can autonomously search the web (DuckDuckGo, Bing, Baidu) and visit webpages to answer complex questions.
*   **Multi-Engine Fallback**: Automatically switches search engines if results are insufficient.
*   **Tool Execution**: Capable of executing defined tools to interact with the environment.
*   **Claude Skills & MCP Agent Integration**: Leverages advanced "Claude skills" for complex reasoning and "MCP agent" for orchestrating multi-task workflows, enabling the agent to complete more sophisticated tasks by combining these capabilities.

### 3. Memory & Personalization
*   **Long-term Memory**: Remembers user preferences, facts, and past conversations to build a continuous relationship.
*   **Persona System**: Customizable system prompts and "Thinking" styles (e.g., the default "Firefly" persona).

### 4. Cross-Platform Display
*   **Standard Mode**: Full-screen chat interface with Live2D character.
*   **Mini-Window Mode**: Compact overlay showing only the Live2D character, ideal for multitasking.
*   **Floating Window (Android)**: System-level floating window that stays on top of other apps.

---

## 🏗️ Architecture & Design

N-T-AI adopts a **Client-Server** architecture to balance performance, privacy, and capability.

### 1. The Frontend (Client) - "The Body"
*   **Tech Stack**: Flutter (Windows, Android, Linux, macOS).
*   **Responsibilities**: 
    *   User Interface (UI) and Interaction.
    *   **Perception**: Handling TTS (Text-to-Speech) generation and STT (Speech-to-Text) recording directly.
    *   **Rendering**: Displaying Live2D models and animations.
    *   **Secure Storage**: Encrypted storage of user configurations and API keys.

### 2. The Backend (Server) - "The Brain"
*   **Tech Stack**: Python (FastAPI).
*   **Responsibilities**: 
    *   **Cognition**: Complex LLM logic, ReAct Agent reasoning, and Tool execution.
    *   **Memory**: Managing long-term memory vectors and databases.
    *   **Asset Service**: Serving static assets (Live2D models) to the frontend.
    *   **Stateless Design**: Does not store user API keys; receives them per-request from the client.

### 3. Why this separation?
This design allows the "Brain" (Backend) to be deployed anywhere—on your local PC, a home server, or a cloud VPS—while the "Body" (App) runs smoothly on your mobile device or laptop. It also prepares the path for a future "Standalone Mode" where the backend logic is ported to Dart for a purely local experience.

### Dual-Mode Operation
- Client-Only: The app connects directly to LLM providers (OpenAI, DeepSeek, etc.) without a local server for lightweight usage.
- Backend Proxy (recommended): The app talks to the local Python backend, which enables ReAct Agents, memory, vision fallback, and advanced tools. The client sends per-request target configs via headers like `X-Target-Api-Key`, `X-Target-Base-Url`, and `X-Target-Model`. The backend remains stateless and uses HTTPS for secure transport.

---

## 📦 Deployment & Installation

We provide multiple ways to deploy the N-T-AI backend system.

### Option A: Docker Deployment (Recommended)
The easiest way to run the backend server. Compatible with Docker Compose, Dokploy, Coolify, etc.

**Full System (Backend + Web Frontend):**
```bash
cd docker/n-t-ai-system
docker-compose up -d
```
*   Frontend: `http://localhost:80`
*   Backend: `http://localhost:8000`

**Backend Only (Astra-Me):**
```bash
cd docker/astra-me
docker-compose up -d
```
*   API: `http://localhost:8000`

### Option B: One-Click Startup Scripts
For local deployment on Windows, Linux, or macOS without Docker.

**Windows:**
Double-click `run_server.bat` in the project root.

**Linux / macOS:**
Run `run_server.sh` in the terminal:
```bash
chmod +x run_server.sh
./run_server.sh
```

### Option C: Manual Installation (Development)
1.  **Backend**:
    ```bash
    cd backend
    pip install -r requirements.txt
    python serve.py
    ```
2.  **Frontend (Flutter)**:
    ```bash
    cd flutter_application
    flutter pub get
    flutter run
    ```

### Option D: Serverless Hosting (Vercel / Render)
- Frontend: Deploy the Flutter Web build as a static site.
- Backend: Deploy the FastAPI backend as serverless functions. A sample configuration is available in the backend directory to guide setup on common platforms.

---

## 🔐 Configuration & Security

### Secure Configuration
N-T-AI prioritizes your data privacy.
*   **Client-Side Storage**: All sensitive data (API Keys for OpenAI, SiliconFlow, etc.) are stored **only** on your client device (Phone/PC) in encrypted secure storage.
*   **Encrypted Transmission**: When the Frontend talks to the Backend:
    *   Configs are passed via HTTP Headers (`X-Target-Api-Key`, `X-Target-Base-Url`).
    *   Communication is secured via **HTTPS** (TLS).
*   **No Server Persistence**: The backend is stateless regarding credentials. It uses the keys provided in the request headers for that specific session.

### Connecting Mobile App to PC Backend
To control the "Brain" on your PC from your Android phone:
1.  **Start Backend**: Run `run_server.bat` on your PC.
2.  **Get IP**: Find your PC's local IP address (e.g., `192.168.1.100`).
3.  **Configure App**:
    *   Open N-T-AI App on Android.
    *   Go to **Settings -> AI Settings**.
    *   Set **Backend URL** to `https://192.168.1.100:8000`.
    *   Ensure both devices are on the same Wi-Fi network.

---

## 🗺️ Roadmap

### Phase 1: Foundation (Completed)
- [x] Cross-platform Flutter Application (Windows/Android/Linux).
- [x] Python Backend (FastAPI) for advanced logic.
- [x] Basic LLM Integration (OpenAI/Local/Custom).
- [x] Live2D Integration (WebView based).

### Phase 2: Feature Migration & Security (Current)
- [x] **Architecture Refinement**: Separation of Client (Body) and Server (Brain).
- [x] **Secure Connectivity**: HTTPS support with self-signed certificate rotation.
- [x] **Frontend-Centric TTS/STT**: Moving audio processing logic to Flutter for lower latency.
- [x] **Deployment Tools**: Docker support and One-click startup scripts.
- [x] **Stateless Backend**: Per-request target configuration via headers (`X-Target-*`), no server-side key storage.
- [x] **Precision Logging**: Improved error logging and diagnostics across frontend and backend.
- [ ] **Enhanced Live2D**: Continued optimization of motion smoothing and expression accuracy.
- [ ] **Claude Skills + MCP**: Evaluate ability boxing and layered loading to integrate specialized task skills alongside MCP tool connectivity.

### Phase 3: Pure Flutter / Standalone Mode (Target)
- [ ] **Serverless Logic**: Porting Python "Brain" logic (Memory, Search, Tools) to Dart.
- [ ] **Local LLM**: Support running small LLMs (e.g., Llama-3-8B-Quantized) directly on Android via MLC-LLM or MediaPipe.
- [ ] **Result**: A fully offline-capable, privacy-focused AI companion app without external dependencies.

### Future Research: Autonomous Behavior
- [ ] **Cognitive Model**: Researching non-deterministic behavioral models to replicate autonomous "life-like" interactions (similar to Neuro-sama).
- [ ] **3D Engine**: Implementing Babylon.js renderer for 3D avatars.

---

## 🧠 Recommended Models

We recommend **[SiliconFlow (硅基流动)](https://cloud.siliconflow.cn/i/oiWI8xjZ)** for a balance of performance and cost.

| Function | Recommended Model | Notes |
| :--- | :--- | :--- |
| **LLM** | `DeepSeek-V3` / `Qwen-2.5` | High intelligence, low cost. |
| **STT** | `SenseVoiceSmall` | Fast, accurate, multilingual. |
| **TTS** | `CosyVoice2-0.5B` | Emotional, natural human voice. |

---

## 🤝 Acknowledgements

This project stands on the shoulders of giants. We gratefully acknowledge:

*   **[N.E.K.O. (Next-gen Emotive Kernel for Operators)](https://github.com/BOHUYESHAN-APB/N.E.K.O.)**: For inspiration on Live2D interaction logic and emotional feedback systems.
*   **[dlp3d.ai](https://github.com/dlp3d/dlp3d.ai)**: For architectural concepts on 3D rendering.
*   **Open Source Community**: For the countless libraries and tools that make this possible.

---

## 📄 License

**Dual-Licensed Software**

*   **Non-Commercial**: [AGPLv3 with Restrictions](LICENSE). Free for personal, non-profit use.
*   **Commercial**: [Commercial License](COMMERCIAL_LICENSE_TERMS.md). Required for business use.

*Built with ❤️ by the N-T-AI Team*
