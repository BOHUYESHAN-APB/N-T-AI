from fastapi import APIRouter, UploadFile, File, HTTPException
from typing import List, Dict
import os
import shutil
import zipfile
import uuid
from pathlib import Path

router = APIRouter()

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "static")
LIVE2D_DIR = os.path.join(STATIC_DIR, "live2d")

# Ensure directories exist
os.makedirs(LIVE2D_DIR, exist_ok=True)

@router.post("/v1/models/upload")
async def upload_model(file: UploadFile = File(...)):
    """
    Upload a Live2D model (ZIP file).
    The ZIP should contain the model files at the root or in a single folder.
    """
    if not file.filename.endswith('.zip'):
        raise HTTPException(status_code=400, detail="Only .zip files are allowed")

    # Create a temporary path for the zip
    temp_zip_path = os.path.join(LIVE2D_DIR, f"temp_{uuid.uuid4()}.zip")
    
    try:
        # Save the uploaded zip
        with open(temp_zip_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # Inspect zip content to find model name and structure
        model_name = os.path.splitext(file.filename)[0]
        extract_path = os.path.join(LIVE2D_DIR, model_name)
        
        # Handle duplicate names
        if os.path.exists(extract_path):
            model_name = f"{model_name}_{uuid.uuid4().hex[:8]}"
            extract_path = os.path.join(LIVE2D_DIR, model_name)
            
        os.makedirs(extract_path, exist_ok=True)
        
        with zipfile.ZipFile(temp_zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_path)
            
        # Cleanup zip
        os.remove(temp_zip_path)
        
        # Find the .model3.json file to confirm validity and get relative path
        model_json_path = None
        
        # First pass: Look for .model3.json
        found_model_file = None
        for root, dirs, files in os.walk(extract_path):
            for f in files:
                if f.endswith('.model3.json'):
                    found_model_file = os.path.join(root, f)
                    break
            if found_model_file:
                break
        
        if not found_model_file:
            # Invalid model, cleanup
            shutil.rmtree(extract_path)
            raise HTTPException(status_code=400, detail="No .model3.json found in the archive")

        # Handle nested folders: if the model file is not in the root of extract_path,
        # we might want to move everything up if it's a single top-level folder.
        # But for now, let's just return the correct relative path.
        # The frontend just needs the path to the .model3.json file relative to /static/live2d/
        
        # Calculate relative path from LIVE2D_DIR
        rel_path = os.path.relpath(found_model_file, LIVE2D_DIR)
        # Normalize slashes for URL
        model_json_path = rel_path.replace("\\", "/")
            
        return {
            "message": "Model uploaded successfully",
            "model_name": model_name,
            "model_path": f"/static/live2d/{model_json_path}"
        }

    except Exception as e:
        if os.path.exists(temp_zip_path):
            os.remove(temp_zip_path)
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/v1/models/list")
async def list_models():
    """
    List available Live2D models.
    """
    models = []
    if not os.path.exists(LIVE2D_DIR):
        return {"models": []}

    for root, dirs, files in os.walk(LIVE2D_DIR):
        for f in files:
            if f.endswith('.model3.json'):
                full_path = os.path.join(root, f)
                rel_path = os.path.relpath(full_path, LIVE2D_DIR)
                
                # Use the top-level folder name as the display name if possible
                parts = Path(rel_path).parts
                if len(parts) > 1:
                    display_name = parts[0]
                else:
                    # If it's at the root or something weird, use the folder name or file name
                    display_name = os.path.basename(os.path.dirname(full_path))
                    if not display_name or display_name == '.':
                        display_name = os.path.splitext(f)[0]
                
                models.append({
                    "name": display_name,
                    "file": f,
                    "path": f"/static/live2d/{rel_path.replace('\\', '/')}"
                })
    
    return {"models": models}

@router.delete("/v1/models/delete")
async def delete_model(path: str):
    """
    Delete a Live2D model by its path.
    The path should be the relative path returned by list_models (e.g. /static/live2d/Folder/file.model3.json).
    This will delete the top-level folder inside LIVE2D_DIR that contains this file.
    """
    # Remove prefix /static/live2d/ if present
    prefix = "/static/live2d/"
    if path.startswith(prefix):
        rel_path = path[len(prefix):]
    else:
        rel_path = path.lstrip("/")

    # Security check: prevent directory traversal
    if ".." in rel_path or rel_path.startswith("/") or rel_path.startswith("\\"):
         raise HTTPException(status_code=400, detail="Invalid path")

    # Determine the top-level folder to delete
    # rel_path is like "ModelName/runtime/file.model3.json"
    parts = Path(rel_path).parts
    if not parts:
        raise HTTPException(status_code=400, detail="Invalid path")
    
    top_folder = parts[0]
    folder_to_delete = os.path.join(LIVE2D_DIR, top_folder)
    
    # Verify that folder_to_delete is actually inside LIVE2D_DIR
    if not os.path.abspath(folder_to_delete).startswith(os.path.abspath(LIVE2D_DIR)):
         raise HTTPException(status_code=400, detail="Invalid path security check")

    if os.path.exists(folder_to_delete) and os.path.isdir(folder_to_delete):
        try:
            shutil.rmtree(folder_to_delete)
            return {"message": f"Model {top_folder} deleted successfully"}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to delete model: {str(e)}")
    else:
        raise HTTPException(status_code=404, detail="Model not found")
