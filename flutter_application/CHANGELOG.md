# 更新日志 (Changelog)

## [0.3.3-beta] - 2025-12-06

### 新增 (Added)
- **语音交互 (Voice Interaction)**:
    - **按住说话 (Push-to-Talk)**: 在聊天界面新增麦克风按钮，支持长按录音、松手发送。
    - **STT/TTS 集成**: 前端已集成语音转文字与文字转语音逻辑 (基于 `record` v5 和 `audioplayers`)。
    - **依赖升级**: 升级 `record` 库至 5.2.0，并解决了 Windows 平台的构建冲突。
    - *注意*: 该功能目前处于代码就绪状态，需在设置中配置 API 后进行测试。

## [0.3.2-beta] - 2025-12-06

### 新增 (Added)
- **云端音频服务集成 (Cloud Audio Integration)**:
    - **后端适配**: 完成了 Python 后端对 SiliconFlow (硅基流动) 音频服务的适配。
    - **API 路由**: 新增 `/api/audio` 路由，支持 STT (语音转文字)、TTS (文字转语音) 及声音克隆功能。
    - **服务层**: 实现了 `AudioService`，支持动态 API Key 和 Base URL 配置，兼容 OpenAI 接口标准。
- **Motion Agent 增强**:
    - **独立模型配置**: `/api/live2d/agent/decide` 现支持通过 Header (`X-Motion-Model` 等) 独立配置模型，允许 Motion Agent 使用与主脑不同的轻量级模型。
    - **自主待机动作 (Autonomous Idle)**: 新增 `/api/live2d/agent/idle` 接口，支持生成随机或基于情绪的待机动作，为实现 "Neuro-sama" 风格的自主运动提供后端支持。

## [0.3.1-beta] - 2025-12-06

### 优化 (Changed)
- **Live2D 交互体验**:
    - **程序化动画 (Procedural Animation)**: 引入非线性动画系统，支持更细腻的动作控制。
    - **平滑过渡 (Smooth Tweening)**: 优化了头部转动 (Look At) 和表情切换的过渡效果，消除了动作僵硬感。
    - **Wink 动作重构**: 实现了自然的眨眼动画（闭眼 -> 保持 -> 平滑睁眼），并支持自动复位。
    - **UI 交互**: 优化了模型锁定按钮的图标逻辑（解锁状态显示为 "🖐"），并默认关闭鼠标跟随以保持视线稳定。
- **后端 (Backend)**:
    - **Motion Agent 协议升级**: 支持发送具名动作指令 (如 "Wink")，为后续更复杂的交互（如 TTS 口型同步）打下基础。

## [0.3.0-beta] - 2025-12-05

### 新增 (Added)
- **Live2D 支持**:
    - 新增 Live2D 模型上传与管理功能（支持 ZIP 包上传）。
    - 新增 Live2D 渲染开关与表情同步开关。
    - 对话界面右上角新增 Live2D 快速开关。
- **设置 (Settings)**:
    - "通用" 设置页新增 "角色模型" 管理入口。
    - 新增 "启用 Live2D" 和 "表情同步" 选项。

### 优化 (Changed)
- **品牌 (Branding)**:
    - 修正 N-T-AI 全称为 "Nexus-Thinking AI"。
- **后端 (Backend)**:
    - 优化模型上传逻辑，支持嵌套文件夹结构的 ZIP 包。
    - 移除所有第三方版权素材，仅保留核心功能代码。

## [0.0.2-beta] - 2025-12-04

### 新增 (Added)
- **智能体配置 (Agent Configuration)**:
    - 新增独立的 "智能体 (Agent)" 设置页面，整合了视觉、绘图、表情等能力的配置。
    - 支持为 "联网搜索" 指定独立的 Agent（默认由主脑负责）。
- **更新日志 (Changelog)**:
    - 软件内置更新日志现在支持 Markdown 渲染，阅读体验更佳。
    - 更新日志内容现在直接读取本地文件，无需网络请求。

### 优化 (Changed)
- **设置 (Settings)**:
    - 优化了 "服务商 (Providers)" 页面，移除了冗余的预设，新增了预设选择弹窗。
    - 优化了 "关于 (About)" 页面，将 "流萤" 更改为英文标识 "Firefly"。
    - 优化了图标适配，支持多种格式。
- **界面 (UI)**:
    - 调整了设置页面的布局，减少了视觉干扰。

## [0.0.1-beta] - 2025-12-03

### 新增 (Added)
- **首次运行向导 (First Run Experience)**:
    - 新增欢迎引导页，支持设置助手名称与系统提示词。
    - 新增 "自动人设生成" 功能，通过 Web Search 自动搜索角色信息并生成 Persona。
    - 新增 "使用默认流萤" 选项，一键回退到系统默认人设。
- **界面与品牌 (UI & Branding)**:
    - 主界面新增双语标题展示 (Assistant Name / System Name / Project Name)。
    - 优化了 "灵动岛" 表情状态栏的显示效果。
- **记忆管理 (Memory)**:
    - 新增 Flutter 原生记忆管理界面，统一了记忆查看与编辑入口。
- **数据隐私 (Privacy)**:
    - 明确区分 "本地备份" 与 "后端数据" 设置。
    - 优化构建流程，确保 MSI 安装包不包含任何用户隐私数据。

### 优化 (Changed)
- **设置 (Settings)**:
    - 重构 `SettingsController`，新增 `assistantName`, `systemPrompt`, `isFirstRun` 等字段。
    - 优化了设置项的持久化逻辑。
- **核心逻辑 (Core)**:
    - `BrainService` 支持动态 System Prompt 注入，不再硬编码。
    - 优化了消息发送逻辑，支持更自然的拟人化分段回复。

### 修复 (Fixed)
- 修复了部分 UI 在 Windows 平台下的显示异常。
- 修复了设置保存时可能出现的竞态条件问题。
