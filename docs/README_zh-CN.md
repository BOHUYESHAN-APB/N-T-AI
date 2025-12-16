# N-T-AI (Nexus-Thinking AI)

![N-T-AI Banner](../flutter_application/assets/images/banner.png)

<div align="center">

[![Version](https://img.shields.io/badge/Version-0.3.7%20Beta-blue)](https://github.com/BOHUYESHAN-APB/N-T-AI)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](../LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20macOS-lightgrey)](https://flutter.dev)
[![Sponsor](https://img.shields.io/badge/Sponsor-爱发电-pink)](https://afdian.com/a/N-T-AI)
[![SiliconFlow](https://img.shields.io/badge/SiliconFlow-推广链接-purple)](https://cloud.siliconflow.cn/i/oiWI8xjZ)

</div>

**N-T-AI** 是一个基于 Flutter 开发的跨平台 AI 助手应用，旨在提供高度可定制、具备情感交互与自主思考能力的 AI 伴侣体验。

---

## 💖 支持与赞助

如果您觉得本项目对您有帮助，欢迎通过以下方式支持我们：

*   **[在爱发电赞助我们](https://afdian.com/a/N-T-AI)**：直接支持我们的开发工作。
*   **[注册 SiliconFlow 账号](https://cloud.siliconflow.cn/i/oiWI8xjZ)**：使用我们的推广链接注册，您将获得 2000万 Tokens，同时也能为我们提供算力支持。

---

## 📖 目录
- [核心特性](#-核心特性)
- [项目与命名](#-项目与命名)
- [架构](#-架构)
- [安装](#-安装)
- [构建与编译](#-构建与编译)
- [开发计划](#-开发计划)
- [许可证](#-许可证)

---

## 🚀 核心特性

### 1. 多模态交互与情感引擎
*   **情感反馈 (Expression Agent)**：内置实时情感推理引擎，根据对话内容展示动态表情（灵动岛风格）。
*   **视觉能力 (Vision)**：
    *   **直接输入**：支持 GPT-4o, Claude 3.5 Sonnet, Qwen-VL 等视觉模型进行多模态交互。
    *   **视觉代理回退 (Vision Fallback)**：如果主模型（如 DeepSeek-Chat）不支持图片，系统会自动调用专用的视觉 Agent（如 Qwen-VL）对图片进行描述，并将描述反馈给主模型，确保无缝的视觉体验。
*   **拟人化消息流**：模拟真实人类的聊天节奏，将长回复拆分为多条短消息发送。

### 2. 自主智能体系统 (ReAct)
*   **网络搜索与浏览**：系统可以自主搜索网络（DuckDuckGo, Bing, Baidu）并访问网页以回答复杂问题。
*   **多引擎回退**：
    *   **搜索**：如果结果不足或受阻，自动按 DuckDuckGo -> Bing -> Baidu 顺序回退。
    *   **图片搜索**：实时验证图片 URL（检查 403/404 错误）并重试不同引擎，确保图片有效显示。
*   **语音交互 (Beta)**：
    *   **STT/TTS**: 支持通过云端 API (如 SiliconFlow) 进行语音转文字和文字转语音。
    *   **按住说话**: 聊天界面集成 Push-to-Talk 功能。
*   **工具执行**：能够执行定义的工具来与环境交互。
*   **Claude Skills 与 MCP Agent 集成**：利用先进的 "Claude 技能" 进行复杂推理，并结合 "MCP Agent" 编排多任务工作流，通过整合这些能力，使 Agent 能够完成更复杂的任务。
*   **纯前端模式 (计划中)**：未来的更新将直接在 Flutter 前端实现这些 Agent 能力，移除对 Python 后端的依赖。

### 3. 记忆与个性化
*   **高度可定制的人设**：
    *   **首次运行向导**：引导用户自定义助手名称与系统提示词。
    *   **自动人设生成**：内置 Web Search 工具，可自动搜索角色资料（如萌娘百科）并生成详细的 System Prompt。
    *   **双语品牌展示**：UI 支持双语标题展示（如 "Firefly / 流萤"），增强沉浸感。
*   **隐私优先的记忆管理**：
    *   **统一记忆管理**：原生界面查看、编辑、删除长期记忆。
    *   **本地优先架构**：所有聊天记录、设置、记忆均存储在本地 SQLite 与 SharedPreferences 中。
    *   **数据主权**：设置中明确区分 "本地备份" 与 "后端数据"。

### 4. 笔记、白板与知识库
*   **文本笔记**: 内置笔记系统，提供基础 Markdown 支持。高级的 Obsidian 风格实时叠加预览正在开发中（详见路线图）。
*   **白板笔记**: 基于 [Excalidraw](https://github.com/excalidraw/excalidraw) 离线副本的可视化笔记，用作本地绘图和草图工具。
*   **RAG 就绪设计 (计划中)**: 笔记、白板导出及外部文档将可接入记忆系统，作为检索增强生成 (RAG) 的数据源，以提升回答准确度和人设一致性。

---

## 🏷️ 项目与命名

为了避免文档与沟通中的歧义，请注意以下术语：

*   **N-T-AI (System)**：项目总称，指代完整的应用套件（Flutter 前端 + Python 后端）。
*   **Astra-Me**：特指 **Python 后端** 服务 (FastAPI)。它是系统的 "灵魂" 或 "系统层"，负责处理复杂逻辑、记忆和工具调用。
*   **Firefly (流萤)**：指代应用内的 **智能体 (Agent)** 逻辑或默认的角色设定。

> **免责声明**：默认 AI 角色名 "Firefly" (流萤) 仅为代号，与游戏《崩坏：星穹铁道》(Honkai: Star Rail) 中的同名角色无直接关联。文中提及的所有游戏名称及相关术语，其版权归属原版权方 (HoYoverse / 米哈游) 所有。

---

## 📦 部署与安装

### 🐳 Docker 部署 (推荐)

我们提供两种 Docker 配置，适配 **Dokploy**、Coolify 等自托管平台或标准 Docker 环境。

#### 1. N-T-AI System (完整版)
同时部署 Flutter Web 前端和 Python 后端。适合希望获得完整 Web 体验的用户。
*   **目录**: `docker/n-t-ai-system`
*   **访问**: 前端 `http://localhost:80`, 后端 `http://localhost:8000`。

#### 2. Astra-Me (仅后端)
仅部署 Python 后端。如果您在手机或电脑上运行 App，只需要后端服务，请使用此版本。
*   **目录**: `docker/astra-me`
*   **访问**: API `http://localhost:8000`。

### ☁️ 免费托管 (Vercel / Render)

#### Vercel
*   **前端**: Flutter Web 应用可作为静态站点部署。
*   **后端 (Astra-Me)**: 支持作为 Serverless Function 部署。我们在 `backend` 目录下提供了 `vercel.json` 配置文件。

---

## 🛠️ 架构

### 双模式运行 (Dual-Mode Operation)

N-T-AI 支持两种运行模式，由 `Enable Python Backend` 设置控制：

1.  **直连模式 (Client-Only)**：
    *   Flutter 应用直接连接到 LLM API (OpenAI, DeepSeek 等)。
    *   轻量级，无需本地服务器。
    *   *限制*：高级功能如记忆、情感分析和网络搜索在此模式下目前不可用。

2.  **后端代理模式 (推荐)**：
    *   Flutter 应用发送请求到本地 Python 后端 (`localhost:8000`)。
    *   **动态配置**：前端通过 HTTP Headers (`X-Target-Api-Key`, `X-Target-Base-Url` 等) 将 API 密钥和模型选择传递给后端。
    *   **全功能**：启用 ReAct Agent、视觉回退、记忆系统和强大的图片搜索验证。

有关交互逻辑的详细技术说明，请参阅 [架构与逻辑文档](architecture_and_logic.md)。

---

*   **前端**：Flutter (Dart)
*   **状态管理**：ChangeNotifier / InheritedWidget (SettingsScope)
*   **存储**：sqflite_common_ffi (SQLite) / shared_preferences
*   **AI 接入**：HTTP REST API (兼容 OpenAI 格式)

---

## 🔐 安全与配置

### 安全配置
N-T-AI 优先保护您的数据隐私：
*   **客户端存储**：所有敏感数据（如 OpenAI、SiliconFlow 等的 API Key）仅保存在您的设备上（手机/电脑），并使用加密的安全存储。
*   **加密传输**：当前端与后端通信时：
    *   使用 HTTP Header 传递配置（如 `X-Target-Api-Key`, `X-Target-Base-Url`）。
    *   通过 **HTTPS**（TLS）加密传输。
*   **无状态后端**：后端不持久化凭据，仅在本次请求中使用客户端提供的参数。

## 📦 安装

1.  **前置条件**：确保已安装 Flutter SDK (3.0+)。
2.  **克隆仓库**：
    `ash
    git clone https://github.com/BOHUYESHAN-APB/N-T-AI.git
    cd N-T-AI/flutter_application
    `
3.  **运行**：
    `ash
    flutter pub get
    flutter run
    `

---

## 🧠 推荐模型

我们推荐 **[SiliconFlow (硅基流动)](https://cloud.siliconflow.cn/i/oiWI8xjZ)**，在性能与成本之间具有良好平衡。

| 功能 | 推荐模型 | 说明 |
| :--- | :--- | :--- |
| **LLM** | `DeepSeek-V3` / `Qwen-2.5` | 高智能、低成本 |
| **STT** | `SenseVoiceSmall` | 速度快、准确度高、多语言 |
| **TTS** | `CosyVoice2-0.5B` | 情感自然、人声逼真 |

## 🔨 构建与编译

### Windows (MSIX)
`ash
cd flutter_application
flutter clean
flutter pub get
dart run msix:create
`
*输出目录: lutter_application/build/windows/x64/runner/Release/*

### Android (APK)
`ash
cd flutter_application
flutter clean
flutter pub get
flutter build apk --release
`
*输出目录: lutter_application/build/app/outputs/flutter-apk/app-release.apk*

---

## 🍎 苹果开发者招募

欢迎拥有苹果设备以及 Apple Developer Program 会员资格的用户来跟我一起协同开发 iOS 以及 macOS 端的应用。

如果没有人来协助参与的话，我会在等发布新 Mac mini 后购买 M5 的 Mac mini 自行处理。

## 🗺️ 开发路线图与未来计划 (Roadmap)

### 第一阶段：基础建设 (当前)
- [x] 跨平台 Flutter 应用 (Windows/Android/Linux)。
- [x] Python 后端 (FastAPI) 处理高级逻辑。
- [x] 基础 LLM 集成 (OpenAI/Local/Custom)。
- [x] Live2D 集成 (基于 WebView)。

### 第二阶段：交互增强 (进行中)
- [x] **架构优化**：客户端 (身体) 与服务端 (大脑) 分离。
- [x] **安全连接**：支持 HTTPS，自签名证书轮换。
- [x] **无状态后端**：通过 `X-Target-*` Header 动态接收前端配置，不在服务端存储密钥。
- [x] **前端 TTS/STT**：将音频相关逻辑迁移到 Flutter，降低延迟。
- [x] **部署工具**：完善 Docker 支持与一键启动脚本。
- [x] **日志增强**：提升前端与后端的错误日志与诊断能力。
- [ ] **高级笔记编辑器**：实现 Obsidian 风格的实时叠加预览与无缝编辑/预览切换。
- [ ] **Live2D 增强**：继续优化动作平滑与表情准确度。
- [ ] **Claude Skills × MCP**：评估“能力装箱 + 分层加载”的工程化方案，与 MCP 工具连接正交组合。
- [ ] **前端迁移**: 优先将后端逻辑 (ReAct Agent, 记忆系统) 迁移至 Flutter 前端，减少对 Python 环境的依赖。
- [ ] **本地模型适配**:
    - 针对开源 STT/TTS 模型 (如 CosyVoice, SenseVoice) 制作 "一键启动包"，解决其配置比传统 LLM (Ollama/LM Studio) 更复杂的问题。
    - 将通过网盘分发这些兼容的副本。
- [ ] **Live2D 增强**: 优化人物神态、动作及表情的互动效果。
- [ ] **3D 引擎**: 基于 Babylon.js 实现 3D 形象渲染 (Havok 物理引擎) - *制作中*。
- [ ] **笔记系统与知识库 RAG**：强化内置 Markdown/Excalidraw 笔记能力，支持导入专业知识库，并作为检索增强生成 (RAG) 的数据源，提升回答准确度与人设一致性。
- [ ] **SQL 记忆系统优化**：针对大规模长期记忆数据设计索引与分层检索策略，保证在记忆变得庞大时仍能高效利用。

### 第三阶段：通用 AI Agent 与高级能力
- [ ] **深度研究 (Deep Research)**: 支持访问专业数据库 (如校园网环境) 进行深度科学研究。
- [ ] **操作系统控制**: 赋予 Agent 对安全容器内虚拟系统 (Linux/Windows) 的完整操控权，使其能操作浏览器、编写文档等。
- [ ] **高级内容创作**: 生成高质量、非套模板的 PPT 和文档。
- [ ] **数字生命/闲置模式**: 实现 "虚拟数字人" 功能，具备自主待机行为。
- [ ] **多模型架构**: 协调大参数量模型与多个小参数量专用模型/Agent 协同工作。

### 第四阶段：工具链与生态
- [ ] **Open Code CLI 集成**：
    - 集成 [open-code-cli](https://opencode.ai/) (MIT License) 的自定义分支，提供类似 Claude Code CLI 的高级命令行能力 (跳过 MCP)。
- [ ] **自定义 Agent**：支持用户配置的 AI Agent 正确添加到项目中，实现更完善的 Function Call 和 Tools Use。
 - [ ] **Claude Skills 能力装箱与分层加载（研究中）**：
    - **工程化范式**：以标准化文件夹封装任务能力（SKILL.md、scripts、references、assets、tests），分层按需加载，显著降低上下文预算。
    - **正交组合**：MCP 负责“如何连接外部工具与数据源”，Skills 负责“如何完成具体任务”，两者组合提供可版本化、可测试、可复用的企业级 Agent 能力库。
    - **最小范式示例**：SKILL.md 定义目标、输入/输出、分层加载策略、MCP 端点与执行步骤，失败回滚记录中间产物与错误日志。
    - **定位与计划**：相比传统 Agent/MCP，更专注于针对性任务能力，适配特定场景；本项目将逐步评估并融入。

---

### 🔮 未来研究：自主运动与认知模型
> **研究目标**：我们旨在复刻 **Neuro-sama** 的自主行为系统，从僵化的预设转向完全由模型驱动的方法。
> *   **运动系统**：开发一个使用视觉反馈循环（第二/第三视角模型）的非确定性 3D/Live2D 运动控制系统。
> *   **认知架构**：研究超越传统 Transformer/Diffusion 的新型架构，用于行为建模。我们目前正在整理一个自监督数据集，以训练一个专门模型，实现更高的人格一致性和有机交互。
> *   **时间线**：这是一个长期研发阶段（约 3 个月），涉及实验性架构设计。

---

## 🤝 致谢 (Acknowledgements)

本项目站在巨人的肩膀上。我们衷心感谢以下开源项目和工具提供的灵感与支持：

*   **[N.E.K.O. (Next-gen Emotive Kernel for Operators)](https://github.com/BOHUYESHAN-APB/N.E.K.O.)**:
    *   感谢其为 **Live2D 交互逻辑**（包括智能参数叠加、模型加载回退机制）以及 **WebRTC 屏幕共享/音频处理** 模块提供的宝贵灵感。
    *   *许可证*: MIT License.
*   **[dlp3d.ai](https://github.com/dlp3d/dlp3d.ai)**:
    *   感谢其为我们正在制作中的 **3D 渲染引擎** 提供的架构灵感。
    *   *许可证*: MIT License.
*   **[Excalidraw](https://github.com/excalidraw/excalidraw)**：
    *   内置白板笔记功能基于 Excalidraw 的离线副本，用于在本地创建和编辑手绘风格的图表和草图，所有数据均保存在本机。
    *   *许可证*: MIT License。我们严格遵守其 MIT 许可条款，未对原项目作任何与许可冲突的修改。
*   **GitHub Copilot**:
    *   感谢 AI 编程助手在开发过程中提供的代码逻辑梳理与支持。

*   **Trae（AI 编程 IDE）**：在模型编程与模型相关实现方面提供了主要支持，帮助完成关键的模型代码实现。

*   **Qoder（AI 编程 IDE）**：尽管 Qoder 在 AI 编程过程中曾带来一些阻碍，但其生成的项目 Wiki 满足基本需求，后续计划基于 Qoder 的 Repo Wiki 功能进一步完善仓库文档；当前 Wiki 可作为可用的起点。
*   **DeepResearchAgent**:
    *   感谢其在分层多智能体架构 (Hierarchical Multi-Agent Architecture) 和 TEA (Tool-Environment-Agent) 协议方面的启发。
    *   *许可证*: MIT License.
*   **free-OKC (OK Computer Virtual Machine)**:
    *   感谢其创新的 "HTML 转 PPTX" 生成逻辑以及沙箱工具执行 (Sandboxed Tool Execution) 的概念。
    *   *许可证*: MIT License.
*   **OpenManus**:
    *   感谢其在 "深度研究" (Deep Research) 规划工作流、浏览器自动化策略以及 ReAct Agent 模式方面的宝贵参考。
    *   *许可证*: MIT License.

我们尊重开源社区，并严格遵守这些上游项目的 MIT 许可条款。

---

## 📄 许可证

**双重许可软件**

*   **非商业用途**：[AGPLv3 附带限制](LICENSE)。免费用于个人、非营利用途。
*   **商业用途**：[商业许可证](COMMERCIAL_LICENSE_TERMS.md)。商业使用需获取授权。

*使用本软件即表示您同意 LICENSE 文件中的条款，并承认作者不承担任何责任。*

---

*Built with ❤️ by the N-T-AI Team*
