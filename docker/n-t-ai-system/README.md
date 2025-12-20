# N-T-AI System Docker Deployment

This directory contains the Docker configuration for deploying the full **N-T-AI System** (Frontend + Backend).

## Definitions

-   **N-T-AI System**: The complete application suite (Flutter Frontend + Python Backend).
-   **Astra-Me**: The Python Backend service.
-   **Firefly**: The Intelligent Agent logic.

## Prerequisites

- Docker
- Docker Compose

## Quick Start

1.  Navigate to this directory:
    ```bash
    cd docker/n-t-ai-system
    ```

2.  Build and run the system:
    ```bash
    docker-compose up --build -d
    ```

3.  Access the application:
    -   **Frontend (Web App):** `http://localhost` (or your server IP)
    -   **Backend API:** `http://localhost:23456` (or your server IP:23456)

## Configuration

### Remote Access

If you are deploying this on a remote server (e.g., VPS) and accessing it from another device:

1.  Open the Web App in your browser (`http://<your-server-ip>`).
2.  Go to **Settings**.
3.  Update the **Backend URL** to `http://<your-server-ip>:23456` (or `http://<your-server-ip>/api` if using the proxy path, though the app currently defaults to root-based API calls).
    *   *Note: The Nginx configuration proxies `/api` to the backend, but the Flutter app may expect the root URL. Using port 23456 is the most reliable method currently.*

### Environment Variables

You can configure backend settings in `docker-compose.yml` under the `backend` service `environment` section.

## Structure

-   **backend/**: Python FastAPI service.
-   **frontend/**: Flutter Web application served via Nginx.
