# Architecture Improvement Plan (Post-Minecraft Update)

Status
- Highest priority after the Minecraft plugin update is completed.
- Planning-only document. No code changes are made here.

Scope
- Focus on the connections between the client "main brain" and other components.
- Validate the relationships among agents, MCP, and backend services.
- Identify improvements and sequencing for a post-Minecraft stabilization phase.

Current Topology (Observed)
- Client (Flutter) sends chat requests to the backend with X-Target-* headers.
- Backend ChatService acts as the primary orchestrator (tools, memory, plugins).
- Deep Research runs as a separate streaming agent pipeline.
- Plugins (Minecraft, Bilibili, Linux Env) are registered in backend startup.
- MCP exists only as a client configuration surface; no runtime integration is visible.

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

Target Architecture (Post-Update)
- Backend-only brain in server mode.
- A single tool registry that includes:
  - Built-in tools (search, visit_page, office generation).
  - Plugins that expose tool endpoints (Minecraft, Linux Env).
  - MCP servers (if enabled).
  - External agents (REST tools) with a single registry.
- Unified metadata for message source and context.
- Live2D command authority determined by mode, not by caller.
- Renderer abstraction layer:
  - Live2D and Live3D are mutually exclusive runtime modes.
  - Shared message bus (chat/motion/expression) feeds the active renderer only.
  - Capability handshake: renderer reports supported motions/expressions so backend can adapt.

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

Execution Plan (After Minecraft Update)
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

Acceptance Criteria
- MCP servers configured in UI can be invoked by the backend tool loop.
- Only one brain is active in server mode.
- External agents appear in a single registry and are callable as tools.
- Live2D motion/expression updates are deterministic and traceable to one source.
- Session isolation prevents cross-user leakage of provider configs.

Open Questions
- Should MCP be allowed in client-only mode, or server-only?
- Do we want per-agent models beyond tool-caller (refiner/researcher) in server mode?
- Is the long-term plan to remove client-side tool loop entirely?

References
- README.md
- docs/architecture_and_logic.md
- docs/external_agent_integration.md
- backend/app/services/chat_service.py
- backend/app/plugins/__init__.py
- flutter_application/lib/core/services/brain_service.dart
- flutter_application/lib/core/services/llm_service.dart
