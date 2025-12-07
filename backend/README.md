# Astra-Me (Fire-fly) Backend

This is the Python backend for the Astra-Me project, implementing the "Digital Life" logic (Persona, Memory, Learning).

## Setup

1.  **Install Python 3.10+**
2.  **Create a virtual environment**:
    ```bash
    python -m venv venv
    .\venv\Scripts\Activate  # Windows
    # source venv/bin/activate # Linux/Mac
    ```
3.  **Install dependencies**:
    ```bash
    pip install -r requirements.txt
    ```
4.  **Configure Environment**:
    Create a `.env` file in this directory:
    ```env
    OPENAI_API_KEY=your_api_key_here
    OPENAI_BASE_URL=https://api.openai.com/v1
    LLM_MODEL=gpt-3.5-turbo
    ```

## Running

```bash
uvicorn main:app --reload
```

The API will be available at `http://127.0.0.1:8000`.
Swagger UI: `http://127.0.0.1:8000/docs`

## API Endpoints

### POST `/chat`
Send a message to Fire-fly.

**Request:**
```json
{
  "message": "你好，我是小明",
  "user_id": "user123"
}
```

**Response:**
```json
{
  "response": "你好呀小明！我是流萤...",
  "emotion": "happy"
}
```
