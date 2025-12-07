# External Agent Integration Specification

This document outlines how to integrate external agents (e.g., Coze, Dify, or custom REST APIs) into the N-T-AI system.

## Overview

N-T-AI supports calling external agents as "Tools" or "Sub-Agents". This allows the main AI (Firefly) to delegate tasks to specialized agents hosted on other platforms.

## Configuration

To add an external agent, you need to configure it in the `settings.json` or via the UI (future implementation).

### Data Structure

An external agent is defined by the `AgentConfig` structure:

```json
{
  "id": "agent_coze_weather",
  "name": "Weather Agent (Coze)",
  "description": "Checks weather information.",
  "providerId": "openai", // Or a custom provider ID if needed
  "enabled": true,
  "meta": {
    "type": "rest_api",
    "endpoint": "https://api.coze.com/open_api/v2/chat",
    "method": "POST",
    "headers": {
      "Authorization": "Bearer YOUR_COZE_API_KEY",
      "Content-Type": "application/json"
    },
    "body_template": {
      "query": "{{input}}",
      "user": "user_123"
    },
    "response_path": "messages[0].content" // JSONPath to extract the answer
  }
}
```

## Integration Protocol

### 1. Discovery
The system loads all enabled agents from the configuration at startup. Agents with `meta.type = "rest_api"` are registered as available tools for the main LLM.

### 2. Invocation
When the main LLM decides to call an agent (e.g., based on the `description`), the system intercepts the call and executes the HTTP request defined in `meta`.

### 3. Response Handling
The system parses the JSON response from the external API using the `response_path` (if provided) or returns the full body. The result is then fed back to the main LLM as a tool output.

## Supported Platforms

### Coze / Dify
Most platforms that expose an OpenAI-compatible chat interface or a simple REST API can be integrated.

- **Coze**: Use the `https://api.coze.com/open_api/v2/chat` endpoint.
- **Dify**: Use the `https://api.dify.ai/v1/chat-messages` endpoint.

## Future Roadmap

- **UI Configuration**: A dedicated "Agents" tab in Settings to add/edit these configurations visually.
- **Standardized API**: A local API standard for N-T-AI plugins.
