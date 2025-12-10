from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Body, Header, Response
from typing import Optional, List
from app.services.audio_service import AudioService
from app.core.config import settings

router = APIRouter()
audio_service = AudioService()

@router.post("/transcriptions")
async def transcribe_audio(
    file: UploadFile = File(...),
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
    model: str = Form("FunAudioLLM/SenseVoiceSmall")
):
    """
    Transcribe audio file to text (STT).
    """
    # Fallback to settings if available (assuming user might add them later) or error
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")
    
    final_api_key = final_api_key or settings.OPENAI_API_KEY # Fallback to generic key if compatible
    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    # Read file content
    file_content = await file.read()
    
    try:
        text = await audio_service.transcribe(
            file_obj=file_content,
            filename=file.filename,
            api_key=final_api_key,
            base_url=base_url,
            model=model
        )
        return {"text": text}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/speech")
async def generate_speech(
    input: str = Body(..., embed=True),
    model: str = Body("FunAudioLLM/CosyVoice2-0.5B", embed=True),
    voice: Optional[str] = Body("alex", embed=True),
    speed: float = Body(1.0, embed=True),
    response_format: str = Body("mp3", embed=True),
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    """
    Generate speech from text (TTS).
    Returns audio binary.
    """
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")
        
    final_api_key = final_api_key or settings.OPENAI_API_KEY
    if not final_api_key:
        print("[AudioRoutes] Missing API Key")
        raise HTTPException(status_code=401, detail="API Key is required")

    # Handle voice fallback for CosyVoice if 'alex' is passed (default)
    # SiliconFlow docs say: "FunAudioLLM/CosyVoice2-0.5B:alex" for system voice.
    original_voice = voice
    original_model = model
    
    # if model and "CosyVoice" in model:
    #     if not voice or voice == "alex":
    #         voice = "FunAudioLLM/CosyVoice2-0.5B:alex"
    #     elif ":" not in voice and "/" not in voice:
    #          # If user passed just "benjamin" etc, try prepending model
    #          voice = f"{model}:{voice}"
    
    print(f"[AudioRoutes] TTS Request: Model={original_model}->{model}, Voice={original_voice}->{voice}, InputLen={len(input)}")

    try:
        audio_content = await audio_service.generate_speech(
            text=input,
            api_key=final_api_key,
            base_url=base_url,
            model=model,
            voice=voice,
            response_format=response_format,
            speed=speed
        )
        
        media_type = f"audio/{response_format}"
        return Response(content=audio_content, media_type=media_type)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/voices")
async def upload_voice(
    file: UploadFile = File(...),
    custom_name: str = Form(...),
    text: Optional[str] = Form(None),
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    """
    Upload a reference audio for voice cloning.
    """
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    final_api_key = final_api_key or settings.OPENAI_API_KEY
    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    # We need to save the file temporarily to pass path to service, 
    # or modify service to accept bytes. 
    # The service uses `open(file_path, "rb")`. Let's modify service or save temp file.
    # Saving temp file is safer for `httpx` file upload usually.
    
    import tempfile
    import os
    import shutil
    
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name
        
    try:
        result = await audio_service.upload_voice(
            file_path=tmp_path,
            custom_name=custom_name,
            text=text,
            api_key=final_api_key,
            base_url=base_url
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

@router.get("/voices")
async def get_voices(
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    """
    List available custom voices.
    """
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    final_api_key = final_api_key or settings.OPENAI_API_KEY
    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    try:
        voices = await audio_service.get_voices(
            api_key=final_api_key,
            base_url=base_url
        )
        return voices
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/voices/{voice_id}")
async def delete_voice(
    voice_id: str,
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    """
    Delete a custom voice.
    """
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    final_api_key = final_api_key or settings.OPENAI_API_KEY
    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    try:
        result = await audio_service.delete_voice(
            voice_id=voice_id,
            api_key=final_api_key,
            base_url=base_url
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
