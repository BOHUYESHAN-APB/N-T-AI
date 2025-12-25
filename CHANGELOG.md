# 更新日志 (Changelog)

## [0.3.14-beta] - 2025-12-25

### 新增 (Added)
- **深度研究 (Deep Research) 视觉风格**:
    - **背景嵌入式问候**: 模拟深度研究界面的视觉效果，将聊天问候语直接嵌入聊天背景，提升界面美感与现代感。
    - **极简 Logo**: 采用了全新的几何美学 Logo，规避了生物恐惧感，并与整体现代 UI 风格保持高度统一。
- **UI/UX 交互升级**:
    - **情景描述编辑器**: 将情景描述（Scenario）功能整合进前端药丸型按钮，操作更直观。
    - **界面去冗余**: 移除了主界面冗余的“Minecraft 第一视角”按钮，进一步简化交互层级。

### 优化 (Changed)
- **Logo 资源体系**: 统一了应用图标与背景 Logo 资源，确保全平台视觉一致性。
- **文档同步**: 完成了中英文文档 (`README.md` & `README_zh-CN.md`) 的全面同步与清理，确保版本信息与功能描述高度一致。

## [0.3.13-beta] - 2025-12-25

### 新增 (Added)
- **Minecraft-mindcraft 插件深度集成**:
    - **核心升级**: 采用 `mindcraft-develop` 最新核心，支持更复杂的生存逻辑与自动化。
    - **AI 名称配置**: 前端新增“AI 代理名称”配置项，支持动态覆盖 Minecraft 角色名，有效防止 AI “自言自语”问题。
    - **全平台 API 桥接**: 自动将 `agent_api_key` 映射至 OpenAI, Gemini, Anthropic, DeepSeek 等 10+ 种主流模型服务商环境变量。
    - **微软登录增强**: 实现了微软 OAuth 验证码的实时捕获与前端 UI 同步显示。

### 修复 (Fixed)
- **进程残留彻底清理**: 在 Windows 下引入 `taskkill /F /T` 强制杀死整个 Node.js 进程树，解决了关闭插件后 MindServer 进程依然滞留的问题。
- **Bilibili 插件 404 故障**: 优化了后端插件注册机制，确保 Bilibili 插件在任何配置下都能正确响应配置接口，修复了动态开启时的 404 错误。
- **Windows 依赖兼容性**: 
    - 移除了导致 Windows 编译失败的 `canvas` 和 `node-canvas-webgl` 强依赖，采用优雅降级处理。
    - 修复了 `eslint` 模块在生产环境下不可用的 `ERR_MODULE_NOT_FOUND` 错误。
- **依赖路径修正**: 修复了 `mineflayer` 的本地路径依赖问题，统一使用 npm 托管版本以提升跨环境兼容性。

### 优化 (Changed)
- **UI 细节优化**: 移除了 Bilibili 配置页按钮上硬编码的端口显示，界面更加简洁。
- **日志净化**: 修复了 `mindserver.js` 中因 `agentName` 未初始化导致的 "undefined restart" 异常日志。

## [0.3.12-beta] - 2025-12-24

### 新增 (Added)
- **VTube Studio (VTS) 深度集成**:
    - **参数同步**: 支持将 N-T-AI 的实时表情数据（面部红晕、头部旋转、表情触发）同步至 VTube Studio。
    - **非阻塞广播**: 采用异步任务机制，确保 Live2D 前端显示与 VTS 同步更新且互不干扰。
    - **预设表情库**: 新增了一套中英文双语触发的预设表情映射逻辑。
- **RAG (检索增强生成) 系统增强**:
    - **后端接口**: 新增 `/api/v1/memory/retrieve` 统一检索接口。
    - **插件联动**: Minecraft 插件现已接入 RAG 系统，能够根据游戏上下文自动检索长期记忆，提升对话的连续性与真实感。
- **项目参考与展示修正**:
    - **Neuro**: 正式列为 VTS 设计模式与集成策略的参考项目。
    - **AIRI**: 移至“同类优秀项目”展示区，明确其作为社区优秀作品的地位，并指出其与本项目共用的 Mineflayer 无头客户端技术路线。
    - **Plan4MC**: 正式列入插件信誉/参考列表，并确立为下一代视觉闭环 Minecraft 插件的核心研究对象。
- **文档体系完善**:
    - 在中英文 README 中同步更新了“开发路线图”，新增了基于 Plan4MC 的视觉闭环智能体开发计划。
    - 细化了“同类优秀项目”章节，加强了与社区项目的互动与展示。

### 优化 (Changed)
- **Minecraft 插件配置同步**: 前端配置的 API 密钥与 URL 现可自动同步至 Minecraft 插件环境，无需手动二次配置。
- **嵌入模型 (Embedding) 稳定性**:
    - 将嵌入请求超时时间提升至 30s。
    - 增加了自动回退机制，当主模型失败时自动尝试使用 `BAAI/bge-m3` 等备选模型。
- **VTS 连接鲁棒性**: 增加了 VTS 服务的自动重连逻辑（30s 周期），提升了长效运行的稳定性。

### 修复 (Fixed)
- **Minecraft 登录故障**: 修复了由于空密码传递导致的 Microsoft 账户登录 `XboxReplayError` 错误。
- **配置覆盖问题**: 修复了 `settings_json` 映射逻辑，确保不会意外覆盖用户在 Minecraft 插件中的默认端口配置。

## [0.3.11-beta] - 2025-12-23

### 新增 (Added)
- **Minecraft 插件重大更新**:
    - **LLM 翻译系统**: 彻底移除 Google Translate，改用主模型进行游戏内聊天翻译，解决 SSL 校验及稳定性问题。
    - **前端深度集成**: Minecraft 消息现在带 `【Minecraft】` 前缀显示在 Flutter 界面，并能正确触发 TTS 语音。
    - **OBS 专场支持**: 新增推流专用页面 (`/plugins/minecraft/stream`)，包含实时 HUD（血量、饥饿、坐标）。
    - **高清采样**: 支持环境变量配置 720P@24FPS 画面采样。
- **外部研究环境**: 预置 `Neuro` 与 `AIRI` 参考项目于 `other-Repository` 文件夹。

### 优化 (Changed)
- **自动化同步机制**: Minecraft 插件保存设置后支持自动防抖重启，无需手动干预。
- **文档体系**: 
    - 统一了中英文 README 特性描述。
    - 移除了“直连模式”相关描述，明确后端代理架构。
    - 修正了 `NEKO` 与 `live2d-py` 的致谢详情。

### 修复 (Fixed)
- **代码诊断**: 清理了 `firefly_screen.dart` 中所有的 Linter 错误及潜在逻辑诊断警告。

## [0.3.10-beta] - 2025-12-22

### 优化 (Changed)
- **设置页整理（通用 / General）**:
    - 按类别分组并改为可折叠展示，减少页面拥挤并提升观感。
    - 展开后才显示分组边框与内容区域，收起时仅显示标题行。
    - 位置: `flutter_application/lib/screens/settings/tabs/general_tab.dart`
- **后端写库频率优化**:
    - `Person.know_times` 改为内存缓冲 + 批量写入（默认阈值 `KNOW_TIMES_BATCH_SIZE=10`）。
    - 位置: `backend/app/services/person_service.py`、`backend/app/core/config.py`
- **SQL 日志开关**:
    - 数据库 `echo` 改为读取 `SQL_ECHO` 配置（默认 false）。
    - 位置: `backend/app/models/database.py`、`backend/app/core/config.py`

<!-- LATEST_LOG_SPLIT: 最新日志与历史日志分割线，请勿删除 -->
---

## [0.3.9-beta] - 2025-12-20

### 优化 (Changed)
- **端口标准化 (Port Standardization)**:
    - **默认端口变更**: 将后端默认端口从 `8000` 统一调整为 `23456`，解决了因端口冲突或不一致导致的连接失败问题。
    - **全局配置同步**: 更新了 `BackendService`, `LLMService`, `BrainService` 及所有插件（如 Bilibili Live）的默认连接逻辑。
    - **文档更新**: 同步更新了 `README`, `DEVELOPMENT_GUIDE` 及 Docker 部署文档，确保所有启动命令和示例 URL 均指向 `23456`。
- **日志净化 (Log Optimization)**:
    - **健康检查过滤**: 后端引入 `EndpointFilter`，自动过滤 `/health` 接口的频繁访问日志，大幅减少控制台噪音，使关键报错和业务日志更易于观察。

### 修复 (Fixed)
- **UI 显示修正**:
    - 修正了设置界面中后端地址的默认提示文本，现在正确显示为 `http://localhost:23456`。
- **连接回退逻辑**:
    - 修复了部分核心服务在未读取到配置时错误回退到旧端口 (8000) 的问题，确保了开箱即用的连接稳定性。

## [0.3.8-beta] - 2025-12-18

### 新增 (Added)
- **深度研究 (Deep Research)**:
    - **自主搜索循环**: 后端实现了自主搜索逻辑，支持多轮搜索决策，并自动生成 Markdown 格式的研究日志 (`research_log.md`)。
    - **项目自动命名**: 新建研究项目时，会根据用户输入自动调用 Planner 模型生成简洁的项目标题。
    - **前端交互增强**: 输入框支持 `Enter` 换行、`Ctrl+Enter` 发送，限制最大显示 5 行并支持滚动。
- **表情包服务 (Meme Service)**:
    - **后端迁移**: 将 Meme 服务从前端迁移至后端 Python 服务，支持基于 Cosine Similarity 的语义搜索。
    - **智能注入**: 在正常聊天模式下，系统会根据对话上下文主动搜索并注入相关表情包图片。
    - **模式隔离**: 确保 Meme 服务仅在普通聊天模式下生效，不干扰深度研究模式。

### 修复 (Fixed)
- **Flutter 构建与 Linter**:
    - 修复了迁移 Meme 服务后遗留的构建错误。
    - 清理了大量前端 Linter 警告（移除死代码、未使用变量）。
    - 修复了 Deep Research 屏幕中输入框缺少 ScrollController 导致的构建错误。
- **Deep Research**:
    - 修复了文件预览中的乱码问题（增强了 HTML/JSON 解析逻辑）。
    - 解决了项目标题在前后端同步不一致的问题。

### 规划 (Roadmap Preview)
- **笔记与知识库联动**:
    - 计划打通深度研究与内置笔记系统，支持将研究成果直接导出为笔记。
    - 引入知识库支持，允许 AI 在研究过程中检索本地知识库内容。
- **Excalidraw 多模态增强**:
    - 针对 Excalidraw 白板笔记，计划引入多模态 RAG 理解，以提升对图文混合内容的检索和理解能力。

## [0.3.7-beta] - 2025-12-16

### 新增 (Added)
- **笔记编辑器 (Note Editor)**:
    - 实现了基础的 Markdown 预览支持 (Split-screen)，允许用户在编辑的同时查看渲染效果。
    - 优化了笔记编辑器的布局，添加了预览切换按钮。

### 文档 (Documentation)
- **README 更新**:
    - 更新了核心特性描述，明确了笔记系统的 Markdown 支持现状及未来 Obsidian 风格预览的规划。
    - 同步了中英文文档的最新状态。

## [0.3.6-beta] - 2025-12-10

- **Live2D 增强**:
    - 优化了待机动作 (Idle Motion) 的触发逻辑，现在会更自然地进行随机动作 (20% 概率，12s 检查周期)。
    - 修复了模型加载的 Fallback 机制，确保旧版模型也能正确加载 Expression 和 Motion。
    - 实现了 Smart Parameter Overlay，允许 Flutter 端实时覆盖控制 Live2D 参数 (如眼神跟随、口型)。
    - **[修复] 口型同步 (Lip Sync)**: 实现了 TTS 音频数据从 Flutter 到 Live2D WebView 的直通机制，确保在所有模式（侧边栏、独立窗口、小窗）下都能正确驱动 Live2D 口型动画。
    - 优化了小窗模式 UI，移除了冗余的 "眼神跟随" 开关。
    - 增加了待机动作触发的绿色高亮日志，方便调试验证。

- **浮动工具栏功能修复**: 独立悬浮窗和侧边栏的专属Web控件（悬浮工具栏）现在可以正确显示，并且不会错误地添加到内置小窗中。已确保在生成浮动窗口的URL时包含 `controls=true` 参数。

### 修复 (Fixed)

## [0.3.5-beta] - 2025-12-09

### 新增 (Added)
- **Live2D 前端与 Flutter 集成改进**:
    - 在内置 WebView 中也显示 Live2D 浮动工具栏（Settings / Lock / Reload），并将工具栏在鼠标移开后的隐藏延迟调整为 1 秒（之前为 500ms）。
    - 新增 `Live2DController`（`lib/widgets/live2d_controller.dart`），用于在 Flutter 中统一向 WebView 注入并执行 Live2D 相关的 JS 调用（lock/toggle/reload/setMouseTracking 等）。
    - `CharacterDisplay` 新增 `floatingUi` 参数；当为 `true` 时构造的模型页面会带上 `floating=true` 参数以启用页面内工具栏。
    - 小窗控件移动到小窗左侧，默认收起为箭头，展开为竖排大按钮；Android 平台因无 hover 行为改为点击展开或不显示悬浮按钮。
    - 修复小窗锁定按钮无效的问题；移除独立浮窗内多余的 JS “Close” 按钮；将 Settings 功能改为切换模型是否跟随鼠标（`mouseTrackingEnabled`）。

- **脚本与构建**:
    - 新增/使用 `scripts/update_version.ps1`，用于从根目录 `CHANGELOG.md` 解析最新版本并更新 `flutter_application/pubspec.yaml` 的 `version:` 字段，同时复制 `CHANGELOG.md` 至 `flutter_application/CHANGELOG.md`。

### 优化 (Changed)
- 优化了 Live2D 模型的加载逻辑，减少了不必要的重复加载。
- 调整了 Live2D 模型的默认参数，使其在启动时表现更自然。
- 修复了 Live2D 模型在特定情况下可能出现的渲染层级问题.


## [0.3.4-beta] - 2025-12-08

### 新增 (Added)
- **表情系统与 Live2D 互斥模式**:
    - 实现表情系统（灵动岛）与 Live2D 完全互斥，二者仅能启用其一。
    - `settings_controller.dart` 新增互斥开关逻辑：启用表情系统时自动关闭 Live2D（侧边栏/悬浮窗）。
    - 右上角显示模式菜单新增"表情系统（灵动岛）"选项，共支持四种模式：表情系统 / Live2D侧边栏 / Live2D悬浮窗 / 全部隐藏。

- **设置界面 UI 重构**:
    - `capabilities_tab.dart` 分离"表情 Agent"和"Live2D 显示"为两个独立分区，解决 UI 分类混淆问题。
    - "表情 Agent" 分区：启用表情 Agent、显示动态表情（灵动岛）、表情推理模型选择。
    - "Live2D 显示" 分区：启用 Live2D 侧边栏、启用 Live2D 悬浮窗。

- **安卓端 Live2D 显示适配规划**:
    - 原独立窗口改为系统级悬浮窗，支持在其他应用之上置顶显示。
    - 主界面侧边栏布局改为右上角内置小窗（约 120x160 dp）。
    - 完整的适配方案已记录在交接文档中。

- **HTTP 加密传输方案规划**:
    - 识别到安卓端 WebView 因 `ERR_CLEARTEXT_NOT_PERMITTED` 无法加载 `http://localhost:8000`。
    - 用户在家庭网络 + 端口映射场景下需要加密传输，但不应强制用户申请 SSL 证书。
    - **推荐方案**：自签名证书 + 证书指纹固定 - 后端启动时自动生成自签名证书，APP 内置证书指纹验证，用户无感知。
    - 备选方案：Cloudflare Tunnel、应用层 AES-256 加密、Tailscale/ZeroTier。

### 优化 (Changed)
- **Token 节约优化**:
    - 验证现有逻辑已正确实现：未开启 Agent 时不会触发 LLM 调用。
    - `enableExpressionAgent` 控制表情推理 LLM 调用，`enableLive2D` 控制 Motion Agent 触发。

### 修复 (Fixed)
- **Kotlin 编译错误修复**:
    - `FloatingWindowChannelHandler.kt` 修复 `MethodCall` 类型错误，添加缺失导入 `import io.flutter.plugin.common.MethodCall`。
    - 所有方法签名从 `MethodChannel.MethodCallHandler.MethodCall` 更正为 `MethodCall`。

### ⚠️ 已知限制 (Known Limitations)

**不推荐在 Android 端使用此项目** 

原因：
- 项目逻辑复杂度高，涉及多个交互系统（表情系统、Live2D、音频服务、Agent 协调）。
- AI 编程在完整理解架构设计上存在困难，导致重复创建已有功能并频繁修改接口变量。
- 当前已产生多项由 AI 造成的逻辑问题，正在人工逐一修复。
- Android 平台特有问题（WebView HTTPS、悬浮窗权限、小屏幕适配）需要额外的架构调整。

**建议用途**：
- 桌面平台（Windows、Linux、macOS）是主要开发和测试目标。
- Android 适配工作建议交由有完整项目上下文的人工开发者。
- 如需在 Android 上使用，请耐心等待稳定版本发布。

---

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
