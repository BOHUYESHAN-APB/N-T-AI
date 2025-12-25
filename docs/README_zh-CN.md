# N-T-AI (Nexus-Thinking AI)

![N-T-AI Banner](../flutter_application/assets/images/banner.png)

> **哲学思考：智能的尺度与未知**
>
> 在探索人工智能的边界时，我们常陷入一种量化比较的困境：以神经节点或参数数量简单衡量系统的智能潜力。然而，这种比较可能误导我们忽略智能的本质。
>
> 人脑拥有约860亿神经元，而当前大模型的参数规模虽已突破万亿，但二者在结构、能耗与运作逻辑上存在根本差异。智能或许并不源于单元数量，而源于 **信息组织的架构、复杂性与涌现性** 。正如蚁群无中央大脑却呈现集体智能，或如边牧仅以有限神经元展现高度的认知与情感能力——智能的表现形式本就多元。
>
> 因此，我们对待人工智能的态度应是开放而审慎的：
> - **不否认其能力** ：AI已能处理语言、推理、创作，其输出具有真实的复杂性与实用性；
> - **不轻易拟人化** ：AI的“理解”基于统计与模式，而非意识与体验；
> - **关注其作为认知伙伴的角色** ：它拓展了知识的边界，也映照出人类智能的独特。
>
> 本项目正是这样一种探索：我们不定义智能，而是尝试构建一个能够对话、学习并反思的系统。我们尊重所有形式的智慧，无论其生于碳基或硅基，无论其以何种形态存在。
>
> 我们邀请你，一起参与这场温和而坚定的探索。

<div align="center">

[![Version](https://img.shields.io/badge/Version-0.3.14%20Beta-blue)](https://github.com/BOHUYESHAN-APB/N-T-AI)
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
*   **深度研究 (Deep Research) 视觉风格**：
    *   **背景嵌入问候**：将聊天问候语直接嵌入聊天背景，提供类似深度研究模式的沉浸式现代视觉体验。
    *   **极简几何 Logo**：采用全新的几何美学 Logo 设计，规避视觉恐惧感，风格更现代、统一。
*   **VTube Studio (VTS) 集成**：支持将 AI 的实时情感与动作同步至 VTube Studio，驱动高精度 2D/3D 模型。
*   **视觉能力 (Vision)**：
    *   **直接输入**：支持 GPT-4o, Claude 3.5 Sonnet, Qwen-VL 等视觉模型进行多模态交互。
    *   **视觉代理回退 (Vision Fallback)**：如果主模型不支持图片，系统会自动调用专用的视觉 Agent 对图片进行语义描述并反馈给主模型。
*   **拟人化消息流**：模拟真实人类的聊天节奏，将长回复拆分为多条短消息发送。
*   **表情包服务 (Meme Service)**：AI 可以根据对话上下文主动发送表情包，增强互动的趣味性。

### 2. 自主智能体系统 (ReAct)
*   **网络搜索与浏览**：系统可以自主搜索网络（DuckDuckGo, Bing, Baidu）并访问网页以回答复杂问题。
*   **Minecraft AI 集成**：
    *   **高阶智能**：集成 **MindCraft**，使 AI 能够具备复杂的面向目标行为在 Minecraft 中进行游戏。
    *   **RAG 增强**：AI 现在可以检索长期记忆，在游戏中也能记得与用户的过往互动。
    *   **视觉 POV 推流**：实时渲染机器人视角的第一人称画面。
    *   **OBS 专用推流 HUD**：提供纯净的推流页面 (`/plugins/minecraft/stream`)，自带实时 HUD。
    *   **配置同步**：前端配置的 API 自动同步，实现真正的开箱即用。
*   **多引擎回退**：搜索与图片验证均具备多级回退逻辑，确保结果的稳定性。
*   **语音交互 (Beta)**：
    *   **云端 STT/TTS**：支持通过云端 API 进行语音转文字/文字转语音。
    *   **虚拟麦克风注入**：可将 TTS 音频注入到虚拟输入设备，用于 Discord/KOOK 等软件。
*   **工具执行**：能够执行定义的工具来与环境交互。
*   **Claude Skills 与 MCP Agent 集成**：利用先进的 "Claude 技能" 进行复杂推理，并结合 "MCP Agent" 编排多任务工作流。

### 3. 记忆与知识库 (RAG)
*   **检索增强生成 (RAG)**：
    *   **多源接入**：支持将文本笔记、白板导出及外部文档接入记忆系统。
    *   **跨插件联动**：记忆系统已开放给 Minecraft 等插件使用，增强跨场景的一致性。
*   **长期记忆管理**：原生界面查看、编辑、删除长期记忆，所有数据均存储在本地 SQLite 中。
*   **高度可定制的人设**：支持通过 Web Search 自动生成角色资料并构建 System Prompt。

### 4. 笔记与白板
*   **文本笔记**: 内置笔记系统，提供基础 Markdown 支持。
*   **白板笔记**: 基于 [Excalidraw](https://github.com/excalidraw/excalidraw) 离线副本的可视化绘图工具。

### 5. 跨平台支持
*   **Windows**: 提供 MSIX 安装包、便携式 ZIP 包以及 Docker 部署支持。
*   **Linux/macOS**: 推荐使用 **Docker** 进行自托管部署。
*   **Android**: 提供 APK 安装包。

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

### 后端代理运行
N-T-AI 目前主要通过后端代理模式运行，以平衡性能、隐私与功能：

*   **后端代理模式 (推荐)**：
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
- [ ] **[最高优先级] 极速响应语音链路**：LLM 流式输出 → 分段 → TTS 尽快播放（暂时搁置）。
- [x] **部署工具**：完善 Docker 支持与一键启动脚本。
- [x] **日志增强**：提升前端与后端的错误日志与诊断能力。
- [x] **Minecraft AI 插件**：实现面向目标的自主行为、实时视角推流及 OBS 专用 HUD。
- [ ] **[新插件] 视觉闭环 Minecraft 智能体**：基于 **Plan4MC** 的强化学习架构，实现具备视觉闭环能力的复杂任务规划与执行。
- [ ] **极速模式（最小编排）**：默认只走主链路，只有必要时才调用额外 Agent/Service。
- [ ] **语音情绪参数联动**：将表情/情绪推理映射到 TTS 风格或参数，优先评估 omni 类模型。
- [ ] **语音聊天软件接入**：虚拟麦克风注入、自动收音与快捷配置（Discord/KOOK 等）。
- [ ] **连续 STT 与内容判定 Agent**：VAD/端点检测、多段合并、是否上送 LLM 判定、必要时先摘要再投喂。
- [ ] **高级笔记编辑器**：实现 Obsidian 风格的实时叠加预览与无缝编辑/预览切换。
- [ ] **Live2D 增强**：
    - 参考 `live2d-py` 的更新链路组织：动作 → 表情 → 眨眼/呼吸 → 拖拽/视线 → 物理 → Pose，提升“自然感”与稳定性。
    - 强化参数叠加：将“动作/表情/口型/音频摆动/微待机”分通道混合，避免互相抢参数导致抽搐或僵硬。
    - 丰富微动作库：更细颗粒的眨眼、呼吸、扫视、轻点头/摇头、身体轻摆等，用于闲置与情绪过渡。
- [ ] **Claude Skills × MCP**：评估“能力装箱 + 分层加载”的工程化方案，与 MCP 工具连接正交组合。
- [ ] **前端迁移**: 优先将后端逻辑 (ReAct Agent, 记忆系统) 迁移至 Flutter 前端，减少对 Python 环境的依赖。
- [ ] **本地模型适配**:
    - 针对开源 STT/TTS 模型 (如 CosyVoice, SenseVoice) 制作 "一键启动包"，解决其配置比传统 LLM (Ollama/LM Studio) 更复杂的问题。
    - 将通过网盘分发这些兼容的副本。
- [ ] **3D 引擎**: 基于 Babylon.js 实现 3D 形象渲染 (Havok 物理引擎) - *制作中*。
- [ ] **笔记系统与知识库 RAG**：强化内置 Markdown/Excalidraw 笔记能力，支持导入专业知识库，并作为检索增强生成 (RAG) 的数据源，提升回答准确度与人设一致性。
- [ ] **SQL 记忆系统优化**：针对大规模长期记忆数据设计索引与分层检索策略，保证在记忆变得庞大时仍能高效利用。

### 第三阶段：通用 AI Agent 与高级能力
- [ ] **深度研究 (Deep Research)**: 初步实现自主搜索循环与 Markdown 研报生成（当前支持 DuckDuckGo），支持访问网络进行深度研究。
    - [ ] **笔记与知识库联动**: 打通深度研究与内置笔记系统，支持将研究成果导出为笔记；支持 AI 检索本地知识库内容辅助研究。
- [ ] **操作系统控制**: 赋予 Agent 对安全容器内虚拟系统 (Linux/Windows) 的完整操控权，使其能操作浏览器、编写文档等。
- [ ] **高级内容创作**: 生成高质量、非套模板的 PPT 和文档。
- [ ] **数字生命/闲置模式**: 实现 "虚拟数字人" 功能，具备自主待机行为。
- [ ] **多模型架构**: 协调大参数量模型与多个小参数量专用模型/Agent 协同工作。
- [ ] **Excalidraw 多模态 RAG**: 针对白板笔记引入多模态 RAG 理解，提升对图文混合内容的检索能力。

### 第四阶段：工具链与生态
- [ ] **Open Code CLI 集成**：
    - 集成 [open-code-cli](https://opencode.ai/) (MIT License) 的自定义分支，提供类似 Claude Code CLI 的高级命令行能力 (跳过 MCP)。
- [ ] **自定义 Agent**：支持用户配置的 AI Agent 正确添加到项目中，实现更完善的 Function Call 和 Tools Use。
 - [ ] **Claude Skills & 深度能力强化 (下一阶段核心研究)**：
    - **首批目标**：旨在增强“深度研究”产出的质量与深度，提升文档编辑与生成的专业性。
    - **用户自定义 (Ingredients)**：设计允许用户自行添加“配方”(Ingredients) 或 Skills 的机制，类似为后厨系统增加新菜谱，实现高度可扩展的 Agent 能力。
    - **系统控制 (第二批)**：利用内置的 Linux 环境（或容器），实现对系统的深度控制与操作。
    - **插件化设计**：对于类似 `nex` 等重型功能，将严格以**插件形式**提供，由用户自主选择安装，防止系统体积无序膨胀。

---

### 🔮 未来研究：自主运动与认知模型
> **研究目标**：我们旨在复刻 **Neuro-sama** 的自主行为系统，从僵化的预设转向完全由模型驱动的方法。
> *   **运动系统**：开发一个使用视觉反馈循环（第二/第三视角模型）的非确定性 3D/Live2D 运动控制系统。
> *   **认知架构**：研究超越传统 Transformer/Diffusion 的新型架构，用于行为建模。我们目前正在整理一个自监督数据集，以训练一个专门模型，实现更高的人格一致性和有机交互。
> *   **时间线**：这是一个长期研发阶段（约 3 个月），涉及实验性架构设计。

---

## 🤝 致谢 (Acknowledgements)

本项目站在巨人的肩膀上。我们衷心感谢以下开源项目与工具提供的灵感与支持。

### 参考开源项目
*   **[N.E.K.O. (Next-gen Emotive Kernel for Operators)](https://github.com/BOHUYESHAN-APB/N.E.K.O.)**：参考了其 **Live2D 交互逻辑** 与 **代码实现**。*许可证*: MIT License.
*   **[dlp3d.ai](https://github.com/dlp3d/dlp3d.ai)**：为 **3D 渲染引擎** 的架构设计提供参考。*许可证*: MIT License.
*   **[Excalidraw](https://github.com/excalidraw/excalidraw)**：内置白板笔记功能基于其离线副本。*许可证*: MIT License.
*   **[live2d-py](https://github.com/EasyLive2D/live2d-py)**：为 Live2D 的 **表情深化细节** 提供了重要帮助。*许可证*: MIT License.
*   **[DeepResearchAgent](https://github.com/SkyworkAI/DeepResearchAgent)**：为分层多智能体架构与 TEA 协议提供启发。*许可证*: MIT License.
*   **[free-OKC (OK Computer Virtual Machine)](https://github.com/kexinoh/free-OKC)**：为 “HTML 转 PPTX” 与沙箱工具执行概念提供参考。*许可证*: MIT License.
*   **[Skywork-Super-Agents](https://github.com/Skywork-ai/Skywork-Super-Agents)**：为 MCP Server 实现等内容提供参考。*许可证*: The Unlicense.
*   **[OpenManus](https://github.com/FoundationAgents/OpenManus)**：为 “深度研究” 工作流、浏览器自动化策略与 ReAct 模式提供参考。*许可证*: MIT License.

### 插件与扩展致谢
*   **blivechat**: 我们的 Bilibili 直播弹幕显示插件参考了该项目开发。*许可证*: MIT. [仓库](https://github.com/xfgryujk/blivechat/)
*   **MindCraft**: 用于 Minecraft AI 代理集成，提供高阶 LLM 驱动的智能。*许可证*: MIT. [仓库](https://github.com/mindcraft-bots/mindcraft)
*   **Mineflayer**: 作为 Minecraft 机器人交互和底层控制的基础引擎。*许可证*: MIT. [仓库](https://github.com/PrismarineJS/mineflayer)
*   **Neuro**: 参考了其 VTube Studio (VTS) 相关部分的设计与集成思路。*许可证*: MIT. [仓库](https://github.com/kimjammer/Neuro)
*   **Plan4MC**: 基于强化学习的 Minecraft 复杂任务规划框架。我们正基于此项目开发新一代视觉闭环 Minecraft 插件。*许可证*: MIT. [仓库](https://github.com/PKU-RL/Plan4MC)

### 🌟 同类优秀项目

我们在此展示并支持社区中其他优秀的 AI 伴侣与智能体项目：

*   **AIRI**: 一个高质量的 AI VTuber 项目。与 N-T-AI 类似，它也利用了无头 Minecraft 逻辑进行游戏交互。我们在此展示以支持开发者并促进 AI 伴侣生态的多样性。[仓库](https://github.com/idootp/AIRI)

### 开发工具
*   **GitHub Copilot**：在开发过程中提供代码辅助能力。
*   **Trae（AI 编程 IDE）**：在模型相关实现与工程改造方面提供支持。
*   **Qoder（AI 编程 IDE）**：提供项目 Wiki 生成能力，用作仓库 Wiki 的起点参考。

我们尊重开源社区，并严格遵守这些上游项目的许可条款。

---

## 🧩 扩展与插件

有兴趣开发插件或了解我们如何集成第三方工具？
请查看我们的 **[插件开发指南](../PLUGIN_DEV_GUIDE.md)**。

---

## 📄 许可证

**双重许可软件**

*   **非商业用途**：[AGPLv3 附带限制](LICENSE)。免费用于个人、非营利用途。
*   **商业用途**：[商业许可证](COMMERCIAL_LICENSE_TERMS.md)。商业使用需获取授权。

*使用本软件即表示您同意 LICENSE 文件中的条款，并承认作者不承担任何责任。*

---

*Built with ❤️ by the N-T-AI Team*
