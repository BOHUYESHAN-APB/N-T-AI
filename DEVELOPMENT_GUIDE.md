# 项目运行指南 (Development Guide)

本文档详细说明了如何配置和运行 N-T-AI 项目的前端、后端以及辅助服务。

## 1. 环境要求 (Prerequisites)

在开始之前，请确保您的开发环境已安装以下工具：

### Flutter (前端)
*   **SDK Version**: `>=3.8.1` (根据 `pubspec.yaml` 配置)
*   **Platform**: Windows (本项目使用了 `webview_windows`，主要针对 Windows 桌面端开发)
*   **Tools**: Visual Studio 2022 (带 C++ 桌面开发工作负载) - Windows 开发必须

### Python (后端)
*   **Version**: Python 3.8+ (建议 3.10+)
*   **Package Manager**: pip

### Node.js (辅助服务/构建工具)
*   **Version**: Node.js 16+ (建议 LTS 版本)
*   **Package Manager**: npm 或 yarn
*   **用途**: 用于运行 `bootstrap-server` 以及构建 Excalidraw 静态资源。

---

## 2. 后端运行 (Backend Setup)

后端位于 `backend/` 目录，基于 FastAPI 开发。

### 步骤：

1.  **进入后端目录**
    ```powershell
    cd backend
    ```

2.  **创建虚拟环境 (可选但推荐)**
    ```powershell
    python -m venv venv
    .\venv\Scripts\Activate.ps1
    ```

3.  **安装依赖**
    ```powershell
    pip install -r requirements.txt
    ```
    *(注意：如果 `requirements.txt` 缺失，请手动安装核心依赖: `pip install fastapi uvicorn pydantic python-dotenv`)*

4.  **运行服务器**
    ```powershell
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
    ```
    *   API 文档地址: `http://localhost:8000/docs`

---

## 3. 前端运行 (Frontend Setup)

前端位于 `flutter_application/` 目录，是一个 Flutter Windows 桌面应用。

### 步骤：

1.  **进入前端目录**
    ```powershell
    cd flutter_application
    ```

2.  **获取依赖**
    ```powershell
    flutter pub get
    ```

3.  **运行应用**
    ```powershell
    flutter run -d windows
    ```

### 注意事项：
*   **Excalidraw 资源**: 项目包含离线版的 Excalidraw，位于 `assets/excalidraw/`。这些资源会在运行时自动部署到应用数据目录。
*   **WebView**: 首次运行时，Windows 可能会提示防火墙权限，请允许。

---

## 4. 辅助服务 (Bootstrap Server)

位于 `docker/bootstrap-server/`，用于 P2P 连接信令（如果项目中使用了相关功能）。

### 步骤：

1.  **进入目录**
    ```powershell
    cd docker/bootstrap-server
    ```

2.  **安装依赖**
    ```powershell
    npm install
    ```

3.  **运行服务**
    ```powershell
    npm start
    ```
    *   默认运行在 `3000` 端口 (或其他配置端口)。

---

## 5. 常见问题 (Troubleshooting)

*   **WebView 白屏**: 检查 `flutter_application/assets/excalidraw/index.html` 是否存在。如果缺失，请参考之前的构建步骤重新生成。
*   **后端连接失败**: 确保后端运行在 `localhost:8000`，且 Flutter 应用中的 API 地址配置正确。
*   **Windows 构建错误**: 确保已安装 Visual Studio 2022 及其 C++ 组件。运行 `flutter doctor` 检查环境健康状况。
