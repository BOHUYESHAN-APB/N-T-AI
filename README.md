# N-T-AI (Nexus-Thinking AI)

![N-T-AI Banner](flutter_application/assets/images/banner.png)

<div align="center">

[![Version](https://img.shields.io/badge/Version-0.3.8%20Beta-blue)](https://github.com/BOHUYESHAN-APB/N-T-AI)
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
*   **Meme Service**: The AI can proactively send memes based on conversation context to enhance engagement (migrated to Python backend for advanced semantic matching).

### 2. Autonomous Agent System (ReAct)
*   **Web Search & Browsing**: The system can autonomously search the web (DuckDuckGo, Bing, Baidu) and visit webpages to answer complex questions.
*   **Multi-Engine Fallback**: Automatically switches search engines if results are insufficient.
*   **Tool Execution**: Capable of executing defined tools to interact with the environment.
*   **Claude Skills & MCP Agent Integration**: Leverages advanced "Claude skills" for complex reasoning and "MCP agent" for orchestrating multi-task workflows, enabling the agent to complete more sophisticated tasks by combining these capabilities.

### 3. Memory & Personalization
*   **Long-term Memory**: Remembers user preferences, facts, and past conversations to build a continuous relationship.
*   **Persona System**: Customizable system prompts and "Thinking" styles.
    *   **Basic**: Sets the core identity and name, ideal for low-latency or pure assistant tasks.
    *   **Advanced**: Adds detailed personality traits, curiosity, and empathy layers.
    *   **Full (Default)**: The complete "Digital Life" experience, including self-awareness, emotional memory, and autonomous behavior simulation.

### 4. Cross-Platform Support
*   **Windows**: MSIX installer, portable ZIP, and Docker support.
*   **Linux**: **Docker** deployment is recommended for self-hosting.
*   **macOS**: **Docker** deployment is strongly recommended due to signing restrictions.
*   **Android**: APK installer available.

### 5. Notes, Whiteboard & Knowledge Base
*   **Text Notes**: Built-in note system with basic Markdown support. Advanced Obsidian-like real-time overlay preview is currently in development (see Roadmap).
*   **Whiteboard Notes**: Visual note type powered by an offline copy of [Excalidraw](https://github.com/excalidraw/excalidraw), used as a local-only drawing surface for sketches and diagrams.
*   **RAG-Ready Design (Planned)**: Notes, whiteboard exports, and external documents will be connectable to the memory system as a Retrieval-Augmented Generation (RAG) source to improve answer accuracy and persona consistency.

---

## 🏗️ Architecture & Design

N-T-AI adopts a **Client-Server** architecture to balance performance, privacy, and capability.

### 1. The Frontend (Client) - "The Body"
*   **Tech Stack**: Flutter (Windows, Android, Linux, macOS).
*   **Responsibilities**: 
    *   User Interface (UI) and Interaction.
    *   **Perception (CRITICAL)**: Handling TTS (Text-to-Speech) generation and STT (Speech-to-Text) recording directly. **This MUST stay in the frontend to guarantee Live2D Lip-Sync accuracy.**
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

## 🍎 Apple Developer Recruitment

We welcome users with Apple devices and Apple Developer Program membership to collaborate with us on developing the iOS and macOS versions of the application.

If no one is available to assist, I plan to purchase an M5 Mac mini after its release to handle this personally.

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
- [ ] **Advanced Note Editor**: Implement Obsidian-style real-time overlay preview and seamless edit/view mode switching.
- [ ] **Enhanced Live2D**: Continued optimization of motion smoothing and expression accuracy.
- [ ] **Claude Skills & Deep Capability Enhancement (Next Core Focus)**:
    - **Phase 1 Goal**: Significantly enhance the quality and depth of "Deep Research" outputs and document editing capabilities.
- [ ] **Knowledge Base & RAG**: Import structured Markdown/notes and external professional knowledge bases, and expose them as a Retrieval-Augmented Generation source for Firefly.
- [ ] **SQL Memory Optimization**: Optimize the long-term memory SQL backend (indexes, query strategies, and data layout) for large-scale memory retrieval without degrading latency.

### Phase 3: Pure Flutter / Standalone Mode (Target)
- [ ] **Serverless Logic**: Porting Python "Brain" logic (Memory, Search, Tools) to Dart.
- [ ] **Local LLM**: Support running small LLMs (e.g., Llama-3-8B-Quantized) directly on Android via MLC-LLM or MediaPipe.
- [ ] **Result**: A fully offline-capable, privacy-focused AI companion app without external dependencies.

### Phase 4: Deep Research & Advanced Capabilities
- [x] **Deep Research**: Preliminary implementation of autonomous search loop and Markdown report generation (currently supports DuckDuckGo).
    - [ ] **Note & Knowledge Base Linkage**: Connect Deep Research with the built-in note system to export findings; allow AI to retrieve local knowledge base content.
- [ ] **OS Control**: Grant Agent full control over a virtual system (Linux/Windows) within a secure container to operate browsers, write documents, etc.
- [ ] **Excalidraw Multimodal RAG**: Implement multimodal RAG for whiteboard notes to improve retrieval and understanding of mixed text-and-image content.

### Future Research: Autonomous Behavior
- [ ] **Cognitive Model**: Researching non-deterministic behavioral models to replicate autonomous "life-like" interactions (similar to Neuro-sama).
- [ ] **3D Engine**: Implementing Babylon.js renderer for 3D avatars.

## 🙏 Acknowledgements

N-T-AI stands on the shoulders of many great open-source projects.

- **N.E.K.O. (Next-gen Emotive Kernel for Operators)**: Thanks to the N.E.K.O. project for inspiration around Live2D interaction logic, emotive parameter layering, WebRTC/audio utilities, and related tooling. *License*: MIT.
- **dlp3d.ai**: Thanks to the dlp3d.ai project for architecture and design ideas used in our 3D rendering and scene management efforts. *License*: MIT.
- **Excalidraw**: The built-in whiteboard note type is powered by an offline copy of the [Excalidraw](https://github.com/excalidraw/excalidraw) project, which is licensed under the MIT License.[^excalidraw-license]
- **GitHub Copilot**: Thanks for code-assist help during development.
- **Trae (AI coding IDE)**: Provided major assistance in model programming and model-related implementation during development.
- **Qoder (AI coding IDE)**: Although Qoder sometimes introduced issues during AI coding, its generated project Wiki satisfied basic needs and will be used as a foundation to further improve the repository Wiki; the current Wiki is an acceptable starting point.
- **DeepResearchAgent**: Thanks for the inspiration on hierarchical multi-agent architecture and the Tool-Environment-Agent (TEA) protocol. *License*: MIT.
- **free-OKC (OK Computer Virtual Machine)**: Thanks for the innovative HTML-to-PPTX generation logic and sandboxed tool execution concepts. *License*: MIT.
- **OpenManus**: Thanks for the insights on "Deep Research" planning workflows, browser automation strategies, and ReAct agent patterns. *License*: MIT.

We respect the open-source community and strictly follow these upstream projects' MIT license terms.

- For a more complete list of upstream projects and inspiration, see the Chinese documentation: [`docs/README_zh-CN.md`](docs/README_zh-CN.md).

[^excalidraw-license]: Excalidraw License (MIT): https://github.com/excalidraw/excalidraw/blob/master/LICENSE

## 🧩 Extending & Plugins

Interested in developing plugins or understanding how we integrate third-party tools?
Check out our **[Plugin Development Guide](PLUGIN_DEV_GUIDE.md)**.

### Future Research: Omni Models, Memory, and Persona
- [ ] **Neuron Count & Digital Life**: Current AI models, despite having parameter counts (often in the trillions) that rival or exceed the synapse counts of some biological organisms, differ fundamentally in architecture. A human brain operates with ~86 billion neurons and ~100 trillion synapses, functioning as a continuous, plastic, and energy-efficient system. In contrast, LLMs are static snapshots of compressed knowledge. N-T-AI acknowledges this distinction: we do not claim to create biological life, but rather to simulate a "Digital Life" form—an entity that uses these massive computational resources to emulate memory, emotion, and agency, creating a convincing and meaningful companion experience.
