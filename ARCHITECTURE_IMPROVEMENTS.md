# Architecture Improvement Plan (Post-Minecraft Update)


Status
- Plugin work is paused to stabilize frontend/backend wiring and config flow.
- Planning-only document. No code changes are made here.

Scope
- Focus on the connections between the client UI/config and backend orchestration.
- Validate the relationships among agents, MCP, memory, renderer, and backend services.
- Identify improvements and sequencing for stabilization before resuming plugin expansion.

System Boundaries (Re-clarified)
- Frontend: UI + config only; no tool loop, no memory retrieval, no plugin orchestration.
- Backend: single brain + tool loop + memory + plugin dispatch.
- Plugins: backend-only execution units; plugin actions are always triggered by backend tools or backend events.
- Renderer (Live2D/Live3D): display-only endpoint driven by backend broadcasts.

Current Topology (Observed)
- Client (Flutter) sends chat requests to the backend with X-Target-* headers.
- Backend ChatService acts as the primary orchestrator (tools, memory, plugins).
- Deep Research runs as a separate streaming agent pipeline.
- Plugins (Minecraft, Bilibili, Linux Env) are registered in backend startup.
- MCP exists only as a client configuration surface; no runtime integration is visible.

Clarified Responsibilities (No-Plugin Baseline)
- Frontend: configuration + UI only; no tool loop, no memory retrieval.
- Backend: single brain, owns tool calling, memory, and plugin dispatch.
- Embedding providers: selected in frontend, executed in backend for vectorization and retrieval.
- Renderer: Live2D/Live3D only receives backend broadcasts; no client-side authority.
- Initiative/auto-chat loops: backend-only when server mode is enabled.

Core Components (Target View)
- UI Config Layer: provider selection, model presets, feature toggles, session UI.
- Backend Orchestrator: ChatService + tool loop + memory + routing.
- Tool Registry: built-in tools + plugins + MCP + external agents, one canonical registry.
- Plugin Manager: lifecycle, capability registry, event bus, permission gate.
- Memory/RAG: embeddings + retrieval + storage; backend only.
- Renderer Gateway: Live2D/Live3D switch + unified motion/expression bus.
- Observability: trace_id logs + per-session telemetry + error surfaces to UI.

AAIF 对齐原则（MCP / goose / AGENTS.md）
- MCP: 作为工具/数据/应用的统一连接协议，后端必须内建 MCP Runtime，并以 MCP 作为 Tool Registry 的基础。
- goose: 强调 local-first 与可复现执行环境，对齐到 Linux Sandbox（Docker 优先）的执行策略与资源隔离。
- AGENTS.md: 作为仓库级指令规范（减少硬编码），统一 agent 行为与工具边界。
  - 由于本仓库不追踪开发用 Markdown，可采用“运行时生成/外部配置”方式引入 AGENTS.md 规则。
- 目标：可互操作、可追踪、可审计、去供应商绑定。

快速迁移路线（最短路径）
M0（立刻，结构对齐）
- 统一 Tool Schema（name/input/output/error/timeout）并与 MCP 对齐。
- 关闭前端工具回路，仅保留 UI 与配置通道。
- 统一 Message Metadata Schema 并强制入口校验。
- 将插件能力注册到 Tool Registry（只通过 tool call 触发）。

M1（短期，MCP 优先落地）
- 后端引入 MCP Runtime，插件工具以 MCP server 形式暴露。
- Tool Registry 变为 MCP 的抽象层（内部映射现有插件）。
- 建立 MCP 安全策略：allowlist + 域名/命令白名单 + 审计日志。

M2（短期，Linux 子系统接入）
- Docker 作为默认执行引擎，WSL/Native 仅作 fallback 且强提示风险。
- 建立资源限制（cpu/mem/disk/timeout）与文件系统隔离策略。
- 将 LinuxEnvPlugin 接入 Tool Registry，提供 run_command 等基础能力。

M3（中期，工作流与治理）
- 增加 local-first 任务编排（可借鉴 goose 的可复现工作流理念）。
- 引入统一权限策略与审计视图，支持回放与追踪。

LLM 功能分类（更细分）
- Realtime (通用对话): 主脑/对话模型，文本优先，默认不依赖视觉。
- Realtime Omni (多模态): 主脑模型自带视觉能力，图片内容直接交给主脑，减少视觉 Agent 调用。
- VLLM (视觉主导): 以视觉为主的 LLM，可作为主脑或独立视觉 Agent 使用。
- 规则：如果主脑是 Omni/VLLM，则默认优先让主脑处理视觉；仅在失败时回退到 Vision Agent。
- Motion 动作类默认是规则/引擎驱动，不强制绑定模型；如需模型驱动动作，归类为 LLM 并在后端按动作策略使用。

Critical Wiring Map
1) Command Path (headful / agent)
   - UI command -> /api/live2d/agent/schedule_chat -> ChatService -> tool calls -> plugin -> UI state updates.
2) Chat Path (normal)
   - UI chat -> /v1/chat/completions -> ChatService -> memory retrieval -> LLM -> Live2D/stream response.
3) Plugin Event Path (backend)
   - Plugin emits event -> PluginManager dispatch -> ChatService/ToolRegistry -> optional UI update.
4) Plugin-to-Plugin Path (proposed)
   - Plugin A -> PluginManager event bus -> Plugin B (by id/capability) -> response -> Plugin A.

Plugin Communication Model (Proposed)
- All plugin communication is mediated by the backend (PluginManager + ToolRegistry).
- Plugins must not directly import/call each other; they exchange messages via an event bus.
- Communication types:
  - plugin.command: backend-to-plugin action request.
  - plugin.event: plugin-to-backend status/telemetry/trigger.
  - plugin.request / plugin.response: plugin-to-plugin RPC routed by PluginManager.
- Message envelope (统一结构):
  - trace_id, session_id, source, target, type, payload, timestamp, priority.
- Responsibility:
  - PluginManager routes events.
  - ChatService decides if events should trigger tool calls or user-facing messages.
  - ToolRegistry exposes plugins as tools, not as hardwired imports.

Plugin-to-Plugin Rules (Safety + Determinism)
- Only one hop through PluginManager (no plugin A -> B -> C chains without a new plan).
- No blocking calls in plugin event handlers; responses are async.
- Plugin A can request B only through declared capability tags.
- All inter-plugin traffic is logged and traceable per session.

Event Bus Semantics (Draft)
- Every message carries trace_id + session_id; without these fields the bus rejects it.
- plugin.request must be answered with plugin.response or timeout within a bounded window.
- plugin.event is fire-and-forget, but must be recorded for audit and replay if needed.
- Retries are allowed only for idempotent events (explicitly marked).
- Errors are normalized into a shared schema and surfaced to ChatService/UI when user-visible.

Key Gaps and Risks
1) Dual-brain ambiguity (client vs backend)
   - Evidence: Client BrainService still contains legacy tool/agent logic; backend is the active brain in server mode.
   - Risk: Confusing behavior, duplicated responsibilities, and unclear authority.
   - Improvement: Define a strict "single brain" policy when backend is enabled. Client becomes UI and transport only.

2) MCP config without runtime wiring
   - Evidence: MCP server configuration exists in the client UI/settings, but no backend runtime or tool routing.
   - Risk: Users can configure MCP servers that never execute.
   - Improvement: Decide MCP runtime location (backend recommended). Provide a concrete runtime and tool registry.

3) AgentConfig and external agent integration are disconnected
   - Evidence: Client AgentConfig exists; backend external_agent_integration.md defines a separate contract.
   - Risk: Two sources of truth and partial functionality.
   - Improvement: Unify agent registry location and data model; choose one canonical path.

4) Specialized agent headers are partially unused
   - Evidence: X-Refiner/X-Researcher headers are sent, but most are not used in backend flow.
   - Risk: False sense of capability and debugging confusion.
   - Improvement: Either use these in backend orchestration or remove/disable them at the client surface.

5) Live2D control authority is split
   - Evidence: Client broadcasts motion/expression while backend also broadcasts.
   - Risk: Conflicting motion commands and non-deterministic visuals.
   - Improvement: Define a single authority per mode. When backend is enabled, backend should be authoritative.

6) Global main_brain_config state
   - Evidence: Backend stores main_brain_config globally.
   - Risk: Cross-session bleed when multiple clients are connected.
   - Improvement: Scope main_brain_config by session_id or user_id.

7) Tool calling protocol split
   - Evidence: Backend supports native tool calls and text-based [TOOL_CALL] parsing.
   - Risk: Two protocols increase complexity and edge cases.
   - Improvement: Standardize on one protocol for server mode (prefer native tool calls).

8) Metadata and source tagging drift
   - Evidence: Client adds source tags (mic/voice/minecraft), but backend routing does not normalize a schema.
   - Risk: Memory and tool behavior diverges across sources.
   - Improvement: Define a unified message metadata schema and enforce at backend entry.

9) Future Live3D integration conflicts with Live2D
   - Evidence: Live2D is currently a first-class transport/renderer; Live3D will be mutually exclusive.
   - Risk: Competing render pipelines, duplicated routes, and ambiguous ownership during mode switches.
   - Improvement: Introduce a renderer abstraction and explicit mode switch (2D/3D), with shared message bus and capability negotiation.

10) Embedding provider propagation gap
    - Evidence: Embedding provider is configured in frontend, but backend usage is inconsistent across entry points.
    - Risk: Memory retrieval fails or falls back to invalid defaults (401/400/402), causing LLM tasks to stall.
    - Improvement: Ensure embedding config is passed and honored for every backend entry (schedule_chat, chat completions, memory rebuild).

11) Plugin-to-plugin undefined routing
    - Evidence: BasePlugin supports handle_event, but no shared bus or routing policy exists.
    - Risk: Hidden direct dependencies or duplicated logic across plugins.
    - Improvement: Formalize event bus + capability registry in backend, and enforce routing rules.

Target Architecture (Post-Update)
- Backend-only brain in server mode.
- A single tool registry that includes:
  - Built-in tools (search, visit_page, office generation).
  - Plugins that expose tool endpoints (Minecraft, Linux Env).
  - MCP servers (if enabled).
  - External agents (REST tools) with a single registry.
- Plugin event bus for plugin-to-backend and plugin-to-plugin messages.
- Unified metadata for message source and context.
- Embedding providers are configured in frontend, executed in backend; frontend never touches vector DB directly.
- Live2D command authority determined by mode, not by caller.
- Renderer abstraction layer:
  - Live2D and Live3D are mutually exclusive runtime modes.
  - Shared message bus (chat/motion/expression) feeds the active renderer only.
  - Capability handshake: renderer reports supported motions/expressions so backend can adapt.

Config Propagation (Backend Proxy Mode)
- Frontend is the source of truth for provider config (LLM/Embedding/Vision/Tool).
- Backend accepts config via headers and must not cache cross-session keys.
- Missing embedding config -> memory disabled + explicit warning to UI.
- Missing LLM config -> request rejected with structured error.
- Vision fallback uses Vision headers only when main model lacks vision.

Unified Message Metadata Schema (Draft)
- Required: session_id, trace_id, message_id, source_type, source_id, timestamp.
- Optional: channel (chat/voice/stream), plugin_id, priority, tags, locale, user_id.
- Source normalization: user | assistant | system | plugin | tool | renderer.
- All inbound messages must be normalized before memory/tool routing.

Session & State Isolation (Draft)
- main_brain_config、provider 选择、工具状态必须按 session_id 隔离。
- 插件状态分为：会话态（跟随 session）与全局态（谨慎、只读或缓存）。
- Renderer 状态按 session 绑定，切换模式必须清理旧状态与订阅。

Tool Registry & Plugin Capability Contract (Draft)
- Tool definition: name, description, input_schema, output_schema, error_schema, timeout_ms.
- Plugin capability: plugin_id, version, tags, tools[], events[].
- Tool calls are the only allowed trigger for plugin actions in server mode.
- Plugin events can request tool calls only through ChatService policy rules.

Error Contract (Draft)
- error_schema: {code, message, category, retryable, trace_id, data}.
- category: config | provider | tool | plugin | renderer | network.
- retryable=true only for safe idempotent operations.

Renderer Gateway Contract (Draft)
- Single active renderer (2D or 3D) with explicit mode switch.
- Inputs: motion, expression, audio, scene_state (optional).
- Outputs: renderer_capabilities, renderer_health, renderer_events.
- Backend owns the renderer switch and broadcasts only to active renderer.

Security & Permission Guardrails (Draft)
- Plugin access is allowlist-based per session and per tool.
- Cross-plugin requests are denied by default unless explicitly granted.
- Force-tool usage requires backend policy approval (no implicit escalation).
- Rate limits and cooldowns apply per plugin to avoid loop storms.

Linux Subsystem Integration (Draft)
- Purpose: provide a safe, reproducible execution sandbox for tools and workflows.
- Priority order:
  - Docker (primary): isolated, reproducible, resource-controlled.
  - WSL (fallback on Windows): limited isolation, warn in UI.
  - Native (fallback on Linux/Mac): lowest isolation, warn + restrict.
- Execution flow:
  - UI request -> ChatService -> ToolRegistry -> LinuxEnvPlugin -> Exec Adapter -> env -> result -> ToolRegistry -> ChatService -> UI.
- Capability surface (tool-level):
  - run_command, read_file, write_file, list_dir, upload/download, package_install (allowlist), process_status, resource_usage.
- Storage model:
  - Session workspace mount (per session_id).
  - Shared cache for dependencies (read-only by default).
  - Artifact export path (explicit allowlist).
  - Cleanup policy on session end + periodic GC.
- Resource policy:
  - cpu_limit, mem_limit, disk_quota, timeout_ms, max_processes.
  - Network policy: allowlist domains or fully offline.
- Security:
  - No root by default; least-privilege user.
  - Host FS is read-only unless explicitly allowed by policy.
  - Deny unsafe syscalls / device access where possible.
- Observability:
  - trace_id on every command.
  - stdout/stderr stored with retention window.
  - tool error schema enforced.
- LaTeX support:
  - Treat LaTeX as a tool inside the Linux sandbox (not a separate system).
  - Provide prebuilt image with texlive + pandoc when enabled.

System-Level AI Functions (Draft, Internal)
- Tool Orchestration: plan -> tool call -> validate -> refine.
- Execution Sandbox: deterministic environment + resource isolation.
- Memory & Retrieval: embeddings + retrieval + ranking.
- Perception/Renderer: visual/audio rendering with explicit authority.
- Governance: policy, permissions, audit logs, and rate limits.
- Session Isolation: per-session config and state boundaries.

Decision Points (Before Implementation)
1) MCP runtime
   - Backend-hosted (recommended): consistent with tool loop and logging.
   - Client-hosted: requires a local tool runner and new IPC bridge to backend.

2) Single brain policy
   - Backend is authoritative when enabled; client tool loop disabled in production.
   - Client mode reserved only for offline/standalone usage.

3) Agent registry ownership
   - Store in backend (preferred for server mode) OR in client with explicit sync.

4) Renderer mode policy
   - Live2D/Live3D mutual exclusion enforced at runtime (single active renderer).
   - Define how mode switching is triggered (user UI vs config flag vs API).

5) Plugin communication policy
   - Event bus is the only allowed path for plugin-to-plugin communication.
   - Decide if any plugin events can auto-trigger tool calls without user confirmation.

Execution Plan (Stabilization First)
Phase 0 - Wiring stabilization (now)
- Confirm schedule_chat and chat completions both accept LLM + embedding configs.
- Enforce memory fallback/disable when embedding config is missing.
- Make LLM/embedding failures visible to UI with clear status.
- Ensure plugin actions are only triggered by explicit tool calls or force_tool.
- Disable client-side initiative loop in backend mode to prevent split-brain behavior.

Phase A - Architecture alignment
- Document the single-brain policy and enforcement conditions.
- Decide MCP runtime location and agent registry ownership.
- Confirm Live2D/Live3D switching policy and renderer abstraction boundary.

Phase B - Integration wiring
- Implement MCP runtime and tool registry (or remove MCP UI until ready).
- Unify external agent config with client AgentConfig or migrate to backend storage.
- Ensure specialized agent headers are used or deprecated.
- Build renderer abstraction and switch gate; adapt Live2D routes to the new interface.

Phase C - Stabilization
- Consolidate tool-call protocol.
- Standardize metadata and source tagging.
- Session-scoped main_brain_config.
- Live2D authority gating for server mode.
- Live3D fallback handling and consistent error reporting when renderer is unavailable.

Phase D - Resume Minecraft (Headful) Plugin Work
- Confirm plugin comms bus + tool registry are stable.
- Implement headful mode flow based on stable backend orchestration:
  - schedule_chat -> tool call -> Minecraft plugin -> headful adapter -> game -> event -> backend -> UI.
- Only after Phase C is green, resume MC headful-specific planning and actions.

Acceptance Criteria
- MCP servers configured in UI can be invoked by the backend tool loop.
- Only one brain is active in server mode.
- External agents appear in a single registry and are callable as tools.
- Live2D motion/expression updates are deterministic and traceable to one source.
- Session isolation prevents cross-user leakage of provider configs.
- Embedding provider configuration from frontend is used by backend memory retrieval without errors.
- Plugin-to-plugin communication is routed through PluginManager and is fully traceable.

Open Questions
- Should MCP be allowed in client-only mode, or server-only?
- Do we want per-agent models beyond tool-caller (refiner/researcher) in server mode?
- Is the long-term plan to remove client-side tool loop entirely?
- Should plugin requests be allowed to trigger tool calls without user confirmation?

References
- README.md
- docs/architecture_and_logic.md
- docs/external_agent_integration.md
- backend/app/services/chat_service.py
- backend/app/plugins/__init__.py
- flutter_application/lib/core/services/brain_service.dart
- flutter_application/lib/core/services/llm_service.dart
