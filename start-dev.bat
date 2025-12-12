@echo off
setlocal

echo [N-T-AI] Starting Development Environment...
echo.

:: Get the current directory (project root)
set "PROJECT_ROOT=%~dp0"
echo Project Root: %PROJECT_ROOT%

:: 1. Start Backend
echo Starting Backend Server...
start "N-T-AI Backend" cmd /k "cd /d "%PROJECT_ROOT%backend" && (if exist venv\Scripts\activate.bat (call venv\Scripts\activate.bat) else (echo Warning: venv not found, using global python)) && python serve.py"

:: 2. Start Frontend (Flutter)
echo Starting Frontend (Windows)...
start "N-T-AI Frontend" cmd /k "cd /d "%PROJECT_ROOT%flutter_application" && flutter run -d windows"

echo.
echo [N-T-AI] Startup commands issued. Please check the new terminal windows.
echo.
pause
