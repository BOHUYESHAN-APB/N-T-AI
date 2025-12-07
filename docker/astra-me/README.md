# Astra-Me (Backend Only)

**Astra-Me** refers to the Python Backend component of the N-T-AI project. It provides the core logic, LLM integration, and API services.

## Deployment

### Docker (Dokploy / Self-Hosted)

1.  Navigate to this directory:
    ```bash
    cd docker/astra-me
    ```

2.  Run with Docker Compose:
    ```bash
    docker-compose up --build -d
    ```

3.  The API will be available at `http://localhost:8000`.

### Vercel

You can deploy this backend to Vercel as a Serverless Function.
Ensure you have the `vercel.json` configuration in the `backend` directory (or root) pointing to `main.py`.
