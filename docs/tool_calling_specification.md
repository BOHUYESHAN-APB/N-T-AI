# N-T-AI Tool Calling Specification

## 1. Overview
This document defines the standard protocol for "Tool Calling" (Function Calling) within the N-T-AI ecosystem. It aims to ensure consistency between the pure Frontend (Client Mode) and the Python Backend (Server Mode), enabling the AI assistant (Firefly) to autonomously use external tools.

## 2. The Agent Protocol (Standard)
The project adopts a **ReAct (Reasoning + Acting)** pattern. The LLM is responsible for deciding *when* to use a tool and *which* tool to use based on the conversation context.

### 2.1 Trigger Format
The LLM invokes a tool by outputting a specific token sequence in its response. The system monitors the output stream for this pattern.

**Format:**
```text
[TOOL_CALL] tool_name: arguments
```

**Examples:**
- `[TOOL_CALL] web_search: flutter dart tutorial`
- `[TOOL_CALL] visit_page: https://example.com/article`
- `[TOOL_CALL] get_current_time:`

**Parsing Rules:**
1.  **Regex**: `\[TOOL_CALL\]\s*([a-zA-Z0-9_]+)\s*:\s*([^\n]*)`
2.  **Robustness**: The parser must handle cases where the LLM prefixes the call with natural language (e.g., "Okay, checking... [TOOL_CALL]...").
3.  **Stop Sequence**: The generation should ideally stop after a tool call is detected to save tokens, though the system must handle full responses.

### 2.2 Execution Loop
1.  **User Input**: User sends a message.
2.  **System Prompt**: Injects tool definitions and instructions (see Section 3).
3.  **LLM Generation**: LLM generates a response.
4.  **Detection**:
    -   If `[TOOL_CALL]` is found:
        1.  Pause generation/display.
        2.  Parse tool name and arguments.
        3.  Execute the corresponding function code.
        4.  Append the tool output to the conversation history as a `user` message (or a specific `tool` role if supported).
        5.  **Recursion**: Send the updated history back to the LLM for the next step.
    -   If no tool call:
        1.  Display response to user.
        2.  Wait for next user input.

### 2.3 Tool Output Format
The result of a tool execution is fed back to the LLM to provide context for the final answer.

**Format:**
```text
Tool Output (tool_name):
<The actual output content>
```

## 3. Standard Tools
All implementations (Client & Server) should support this core set of tools.

### 3.1 `web_search`
-   **Purpose**: Search the internet for up-to-date information.
-   **Arguments**: `query` (String) - Keywords to search.
-   **Behavior**:
    -   Returns a list of search results (Title, URL, Snippet).
    -   **Crucial**: Does NOT automatically visit pages. Returns summaries so the LLM can decide which link to visit next.
-   **Output Example**:
    ```text
    Search Results for "Flutter":
    1. Flutter - Build apps for any screen
       URL: https://flutter.dev
       Snippet: Flutter transforms the app development process...
    ```

### 3.2 `visit_page`
-   **Purpose**: Deep read of a specific URL.
-   **Arguments**: `url` (String) - The full URL.
-   **Behavior**:
    -   Fetches the HTML content.
    -   Extracts main text (readability mode).
    -   Extracts relevant images as `[IMAGE: url]` tags.
-   **Output Example**:
    ```text
    Page Title: Flutter Documentation
    Content: Flutter is an open source framework...
    Relevant Images:
    [IMAGE: https://flutter.dev/logo.png]
    ```

### 3.3 `get_current_time`
-   **Purpose**: Get the current system date and time.
-   **Arguments**: None.
-   **Output Example**: `2025-12-04 15:30:00`

## 4. Implementation Status & Divergence

### 4.1 Client Mode (Flutter / Pure Frontend)
-   **Status**: ✅ **Fully Compliant**
-   **Implementation**: `lib/core/services/brain_service.dart`
-   **Logic**: Implements the full ReAct loop. Parses `[TOOL_CALL]`, executes locally, and loops.

### 4.2 Server Mode (Python Backend)
-   **Status**: ⚠️ **Partial / Pipeline**
-   **Implementation**: `backend/app/services/chat_service.py`
-   **Logic**: Currently uses a **Pre-computation Pipeline**.
    -   If `X-Enable-Browser` header is true, it searches *before* calling the LLM.
    -   It injects search results into the System Prompt.
    -   It does **not** currently support the `[TOOL_CALL]` loop for autonomous multi-step reasoning.
-   **Recommendation**: The Backend should be updated to support the ReAct loop to match the Client Mode's flexibility.

## 5. Best Practices for Future Tools
1.  **Atomic**: Tools should do one thing well.
2.  **Descriptive**: The system prompt description is the API documentation for the LLM. Be precise.
3.  **Error Handling**: Tools must never crash the chat. Return error messages as strings (e.g., "Error: 404 Not Found") so the LLM can handle them gracefully.
4.  **Privacy**: Do not send user credentials or sensitive data to external tools unless explicitly authorized.
