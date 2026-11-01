# Live2D Module & Roadmap

This directory contains the Live2D rendering engine and assets for Project N-T-AI (Astra-Me).

## Current Features
- **Core Rendering**: Supports Live2D Cubism 4.0+ models using PIXI.js v7 and `pixi-live2d-display`.
- **Interactive Controls**: Floating toolbar for common actions (Voice, Screen Share, Settings, Lock Position, Reload).
- **Expression/Motion**: Basic support for playing expressions and motions triggered by the backend.
- **Lip Sync**: Basic lip synchronization support.

## Development Roadmap (Planned Features)

### 1. Transparent & Floating Window Support
- **Transparent Background**: The Live2D renderer must support a fully transparent background to blend seamlessly with the desktop or mobile UI.
- **PC Standalone Window**: A dedicated, transparent window mode for PC, optimized for streaming (OBS) and desktop companionship.
- **Mobile Floating Widget**: A floating, transparent Live2D widget for Android/iOS that stays on top of other apps.
- **Hide Chat Interface**: Option to completely hide the text chat UI, leaving only the character visible.

### 2. Advanced Model Control (Agent-Based)
- **Dedicated Control Agent**: A specialized AI agent (separate from the main conversation "Brain") to control the model's non-verbal behavior.
    - **Context Awareness**: The agent analyzes the current context to determine appropriate expressions and motions autonomously.
    - **Independence**: It does not strictly follow the main LLM's instructions, adding unpredictability and "life" to the character.
- **Gaze Control**:
    - **Disable Mouse Tracking**: Option to disable the default "follow mouse" behavior.
    - **Agent-Directed Gaze**: The Control Agent decides where the model looks (e.g., at the user, away in thought, at a specific screen region).

### 3. Immersive Communication
- **Internalized Thoughts**: Convert italicized text (thoughts/emotions) from the LLM into model actions/expressions instead of displaying them as text.
- **Subtitle Systems**:
    - **Transparent Overlay**: Display subtitles on a transparent web layer at the bottom of the screen.
    - **Speech Bubbles**: Display text in comic-style speech bubbles directly above the model's head.
- **TTS/STT Integration**: Full integration with Text-to-Speech and Speech-to-Text for voice interaction.

## Directory Structure
- `libs/`: Core libraries (PIXI.js, Cubism Core, pixi-live2d-display).
- `index.html`: Main entry point for the renderer.
- `live2d.js`: Main logic for model management and interaction.
- `status.html`: Diagnostic page for checking library loading status.

## Usage

1.  **Upload Models**: Use the application's "Character Management" interface to upload Live2D model packages (ZIP files).
2.  **Manual Installation**: You can also manually extract Live2D model folders here.
    *   Ensure the folder structure is correct (e.g., `model_name/model_name.model3.json`).

## Note

No default models are included to respect intellectual property rights. Please provide your own legally obtained Live2D models.
