from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Dict, Any
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
    plugin = _get_linux_plugin()
    status = plugin.get_status()
    if status.get("type") == "docker" and status.get("status") != "ready":
        if plugin.config.get("docker", {}).get("start_on_demand", True):
            await plugin._ensure_docker_container()
            status = plugin.get_status()
    if not status.get("plugin_detected") and status.get("status") != "native":
        raise HTTPException(status_code=404, detail="Linux environment not found")
    return {"message": "Connected", "info": status}

@router.get("/config")
async def get_linux_config():
    """Get the Linux environment config."""
    plugin = _get_linux_plugin()
    return {"config": plugin.config}

@router.post("/config")
async def update_linux_config(request_data: Dict[str, Any]):
    """Update the Linux environment config."""
    plugin = _get_linux_plugin()
    config = request_data.get("config", request_data)
    if not isinstance(config, dict):
        raise HTTPException(status_code=400, detail="Invalid config payload")
    if isinstance(config.get("docker"), dict):
        existing = plugin.config.get("docker", {}) or {}
        config = {**config, "docker": {**existing, **config["docker"]}}
    plugin.config.update(config)
    await plugin.on_config_updated()
    return {"status": "ok", "config": plugin.config}
