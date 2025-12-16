# Plugin Development Guide

This guide explains how to extend N-T-AI with plugins and how we integrate third‑party tools such as Excalidraw for the whiteboard note type.

## Goals
- Add capabilities without changing core app logic.
- Keep credentials on the client; the backend stays stateless.
- Maintain clear boundaries between UI (Flutter) and cognition/tools (Python backend).

## Architecture Overview
- Frontend (Flutter):
  - UI, TTS/STT, Live2D rendering, Notes/Whiteboard pages.
  - Sends per‑request headers (e.g., `X-Target-Api-Key`, `X-Target-Base-Url`) when using the backend.
- Backend (FastAPI):
  - ReAct orchestration, memory retrieval, tool routing.
  - Exposes HTTP endpoints; does not persist client credentials.

## Plugin Types
- UI Plugins (Flutter):
  - Widgets, panels, or screens (e.g., expression panel, whiteboard).
  - Access app settings via `SettingsScope`.
  - Persist plugin data using existing note/memory services or your own local store.
- Backend Tools (FastAPI):
  - Define tool handlers for search, scraping, or domain tasks.
  - Return structured outputs the client can render.

## Integration Points
- Headers:
  - Use `X-Session-Id` to isolate per‑conversation context.
  - Use `X-Target-*` to pass provider and model parameters.
- Memory:
  - Long‑term memory retrieval endpoints can be extended to include plugin data (planned RAG).
  - Ensure embeddings and storage formats are consistent (JSON arrays for vectors).

## Excalidraw Whiteboard
- We ship an offline copy of Excalidraw assets bundled with the app for local use.
- License: MIT (see upstream license).
- Usage:
  - Assets are copied to an app‑data directory on first use.
  - The whiteboard screen loads `index.html` via a `WebView` and saves scene JSON into a note entry.
  - Data remains on device; no network calls are required.

## RAG & Knowledge Base (Planned)
- Notes (Markdown) and Whiteboard exports will be indexable for retrieval‑augmented generation.
- Import professional knowledge bases (Markdown, CSV, PDFs) and expose them as a queryable source.
- SQL memory optimization will include:
  - Proper indexing strategies.
  - Batched embedding generation.
  - Hybrid retrieval (vector + keyword fallback) for robustness.

## Guidelines for New Plugins
- Keep secrets in client secure storage.
- Prefer stateless HTTP endpoints on the backend.
- Provide graceful error states and retries.
- Avoid blocking UI; use async operations with progress indications.

## Contributing
- Fork the repository and add your plugin under `flutter_application/lib/plugins/` (UI) or `backend/app/plugins/` (server).
- Include minimal docs and tests for your plugin.
- Submit a pull request describing the capability and integration points.

