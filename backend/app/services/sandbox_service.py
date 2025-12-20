"""
Sandbox Service
Manages isolated Python execution environments (sessions) for the Coding Agent.
Inspired by free-OKC's IPythonTool.
"""

import io
import contextlib
import traceback
import subprocess
import shlex
import sys
import datetime
import os
import shutil
from pathlib import Path
from typing import Dict, Any, List, Optional
from uuid import uuid4

class SandboxSession:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self._globals: Dict[str, Any] = {}
        self.created_at = datetime.datetime.now()
        
        # Enforce strict workspace isolation (free-OKC style)
        # Use absolute path to avoid ambiguity
        base_workspace = Path(os.getcwd()) / "workspace"
        self.workspace_dir = base_workspace / self.session_id
        
        # Ensure pristine state for new sessions
        if self.workspace_dir.exists():
            try:
                shutil.rmtree(self.workspace_dir)
            except Exception as e:
                print(f"Warning: Could not clear existing workspace {self.workspace_dir}: {e}")
        
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        
        # Change CWD to workspace for subprocess calls
        self._cwd = str(self.workspace_dir.absolute())
        print(f"[Sandbox] Initialized session {session_id} at {self._cwd}")

    def execute(self, code: str) -> Dict[str, Any]:
        """
        Executes Python code or Shell commands (prefixed with !) in this session.
        Maintains global state between calls.
        """
        shell_outputs: List[str] = []
        python_code_lines: List[str] = []
        
        for line in code.splitlines():
            stripped = line.strip()
            if stripped.startswith("!"):
                # Shell command execution
                command = stripped[1:]
                try:
                    # Execute in workspace directory
                    completed = subprocess.run(
                        shlex.split(command),
                        capture_output=True,
                        text=True,
                        shell=True,
                        cwd=self._cwd
                    )
                    combined = (completed.stdout or "") + (completed.stderr or "")
                    shell_outputs.append(f"$ {command}\n{combined.strip()}")
                except Exception as e:
                     shell_outputs.append(f"$ {command}\nError: {str(e)}")
            else:
                python_code_lines.append(line)
                
        python_code = "\n".join(python_code_lines)
        
        stream = io.StringIO()
        error_text = None
        
        if python_code.strip():
            try:
                # Capture stdout
                with contextlib.redirect_stdout(stream):
                    # Set CWD for Python execution
                    original_cwd = os.getcwd()
                    os.chdir(self._cwd)
                    try:
                        # Execute in the persistent _globals dictionary
                        exec(python_code, self._globals, self._globals)
                    finally:
                        os.chdir(original_cwd)
            except Exception as exc:
                error_text = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))

        output_parts = [part for part in [stream.getvalue().strip(), *shell_outputs] if part]
        output_text = "\n\n".join(output_parts).strip()
        
        success = error_text is None
        
        return {
            "success": success,
            "output": output_text,
            "error": error_text,
            "globals_keys": list(self._globals.keys()),
            "workspace": self._cwd
        }
    
    def cleanup(self):
        try:
            if self.workspace_dir.exists():
                shutil.rmtree(self.workspace_dir)
        except Exception as e:
            print(f"Error cleaning up sandbox {self.session_id}: {e}")

    def reset(self):
        self._globals.clear()
        # Clean and recreate workspace? For now, keep files.

import datetime

class SandboxService:
    def __init__(self):
        self._sessions: Dict[str, SandboxSession] = {}

    def create_session(self) -> str:
        session_id = str(uuid4())
        self._sessions[session_id] = SandboxSession(session_id)
        return session_id

    def get_session(self, session_id: str) -> Optional[SandboxSession]:
        return self._sessions.get(session_id)

    def delete_session(self, session_id: str):
        if session_id in self._sessions:
            self._sessions[session_id].cleanup()
            del self._sessions[session_id]

    def execute_code(self, session_id: str, code: str) -> Dict[str, Any]:
        session = self.get_session(session_id)
        if not session:
            # Auto-create if not exists (or raise error)
            # Let's auto-create for smoother UX, or fail?
            # User said "session based", so maybe we should return error if session expired.
            # But for now, let's just return error to enforce explicit session management
            return {"success": False, "error": "Session not found", "output": ""}
        
        return session.execute(code)

# Singleton instance
sandbox_service = SandboxService()
