from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Any, Optional
from app.plugins import get_plugin
from app.plugins.linux_env.plugin import LinuxEnvPlugin

router = APIRouter()

class CommandRequest(BaseModel):
    command: str

def _get_linux_plugin() -> LinuxEnvPlugin:
    plugin = get_plugin("linux_env")
    if not plugin or not isinstance(plugin, LinuxEnvPlugin):
        raise HTTPException(status_code=503, detail="Linux Environment Plugin not active")
    return plugin

@router.get("/status")
async def get_linux_status():
    """Get the status of the Virtual Linux Environment."""
    return _get_linux_plugin().get_status()

@router.post("/execute")
async def execute_linux_command(request: CommandRequest):
    """Execute a command in the Linux environment."""
    return await _get_linux_plugin().execute_command(request.command)

@router.post("/connect")
async def connect_linux():
    """
    Initiate a connection (Handshake).
    For now, just checks availability.
    """
    status = _get_linux_plugin().get_status()
    if not status.get("plugin_detected") and status.get("status") != "native":
        raise HTTPException(status_code=404, detail="Linux environment not found")
    return {"message": "Connected", "info": status}
