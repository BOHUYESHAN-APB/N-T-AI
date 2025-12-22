from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Body, Header, Response
from fastapi.responses import StreamingResponse
from typing import Optional, List
import asyncio
import base64
from app.services.audio_service import AudioService
from app.core.config import settings
from app.core.logger import logger

router = APIRouter()
audio_service = AudioService()

def _normalize_cosyvoice_voice(model: str, voice: Optional[str]) -> Optional[str]:
    if not model or "CosyVoice" not in model:
        return voice
    if not voice or voice == "alex":
        return "FunAudioLLM/CosyVoice2-0.5B:alex"
    if voice == "sys_female_01":
        return "FunAudioLLM/CosyVoice2-0.5B:alex"
    if voice == "sys_male_01":
        return "FunAudioLLM/CosyVoice2-0.5B:benjamin"
    if ":" not in voice and "/" not in voice:
        known_system_voices = ["alex", "anna", "bella", "benjamin", "charles", "diana"]
        if voice in known_system_voices:
            return f"{model}:{voice}"
    return voice

@router.get("/devices")
async def list_devices():
    try:
        return audio_service.list_audio_devices()
    except RuntimeError as e:
        logger.error(f"[AudioRoutes] list_devices runtime error: {e}", exc_info=True)
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        logger.error(f"[AudioRoutes] list_devices unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/loopback/capture")
async def loopback_capture(
    duration_seconds: float = Body(5.0, embed=True),
    device_index: Optional[int] = Body(None, embed=True),
    samplerate: int = Body(48000, embed=True),
    channels: int = Body(2, embed=True),
):
    try:
        logger.info(
            f"[AudioRoutes] loopback_capture request: duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels}"
        )
        result = await asyncio.to_thread(
            audio_service.capture_loopback_wav_bytes_with_info,
            duration_seconds,
            device_index,
            samplerate,
            channels,
        )
        wav_bytes = result["wav_bytes"]
        import io
        import wave
        used_sr = samplerate
        used_ch = channels
        try:
            with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
                used_sr = int(wf.getframerate())
                used_ch = int(wf.getnchannels())
        except Exception:
            used_sr = samplerate
            used_ch = channels
        return {
            "format": "wav",
            "duration_seconds": duration_seconds,
            "requested": {"device_index": device_index, "samplerate": samplerate, "channels": channels},
            "used": {
                "device_index": (result.get("used") or {}).get("device_index"),
                "samplerate": used_sr,
                "channels": used_ch,
                "mode": (result.get("used") or {}).get("mode"),
                "device_name": (result.get("used") or {}).get("device_name"),
            },
            "audio_b64": base64.b64encode(wav_bytes).decode("ascii"),
        }
    except RuntimeError as e:
        logger.error(
            f"[AudioRoutes] loopback_capture runtime error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(
            f"[AudioRoutes] loopback_capture value error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            f"[AudioRoutes] loopback_capture unexpected error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/loopback/measure")
async def loopback_measure(
    duration_seconds: float = Body(1.0, embed=True),
    device_index: Optional[int] = Body(None, embed=True),
    samplerate: int = Body(48000, embed=True),
    channels: int = Body(2, embed=True),
):
    try:
        logger.info(
            f"[AudioRoutes] loopback_measure request: duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels}"
        )
        stats = await asyncio.to_thread(
            audio_service.measure_loopback_level,
            duration_seconds,
            device_index,
            samplerate,
            channels,
        )
        return {"status": "ok", "stats": stats}
    except RuntimeError as e:
        logger.error(
            f"[AudioRoutes] loopback_measure runtime error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(
            f"[AudioRoutes] loopback_measure value error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            f"[AudioRoutes] loopback_measure unexpected error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/debug/resolve-output-device")
async def resolve_output_device(
    device_index: Optional[int] = Body(None, embed=True),
):
    try:
        logger.info(f"[AudioRoutes] resolve_output_device request: device_index={device_index}")
        resolved = await asyncio.to_thread(audio_service.resolve_output_device_index, device_index)
        devices = audio_service.list_audio_devices()
        dev_list = (devices.get("devices") if isinstance(devices, dict) else None) or []
        src_name = None
        dst_name = None
        try:
            if device_index is not None and 0 <= device_index < len(dev_list):
                src_name = (dev_list[device_index] or {}).get("name")
        except Exception:
            src_name = None
        try:
            if resolved is not None and 0 <= resolved < len(dev_list):
                dst_name = (dev_list[resolved] or {}).get("name")
        except Exception:
            dst_name = None
        return {
            "status": "ok",
            "requested": {"device_index": device_index},
            "resolved": {"output_device_index": resolved},
            "names": {"requested_device_name": src_name, "resolved_device_name": dst_name},
        }
    except RuntimeError as e:
        logger.error(f"[AudioRoutes] resolve_output_device runtime error: {e} (device_index={device_index})", exc_info=True)
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        logger.error(f"[AudioRoutes] resolve_output_device unexpected error: {e} (device_index={device_index})", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/debug/play-tone")
async def play_tone(
    device_index: Optional[int] = Body(None, embed=True),
    device_role: str = Body("output", embed=True),
    frequency_hz: float = Body(880.0, embed=True),
    duration_seconds: float = Body(0.6, embed=True),
    samplerate: int = Body(48000, embed=True),
    channels: int = Body(2, embed=True),
):
    if device_role not in ["output", "input"]:
        raise HTTPException(status_code=400, detail="invalid device_role")
    try:
        logger.info(
            f"[AudioRoutes] play_tone request: role={device_role}, device_index={device_index}, hz={frequency_hz}, duration={duration_seconds}, sr={samplerate}, ch={channels}"
        )
        wav_bytes = await asyncio.to_thread(
            audio_service.generate_test_tone_wav_bytes,
            frequency_hz,
            duration_seconds,
            samplerate,
            channels,
        )
        used_device_index = device_index
        if device_role == "input":
            if device_index is not None:
                used_device_index = await asyncio.to_thread(audio_service.resolve_output_device_index, device_index)
                if used_device_index is None:
                    raise HTTPException(status_code=400, detail="cannot_resolve_output_device")
        play_info = await asyncio.to_thread(audio_service.play_wav_bytes, wav_bytes, used_device_index)
        return {
            "status": "ok",
            "requested": {"device_index": device_index, "device_role": device_role},
            "used": {"output_device_index": used_device_index},
            "tone": {
                "frequency_hz": frequency_hz,
                "duration_seconds": duration_seconds,
                "samplerate": samplerate,
                "channels": channels,
            },
            "play": play_info,
        }
    except HTTPException:
        raise
    except RuntimeError as e:
        logger.error(
            f"[AudioRoutes] play_tone runtime error: {e} (role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(
            f"[AudioRoutes] play_tone value error: {e} (role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            f"[AudioRoutes] play_tone unexpected error: {e} (role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/play")
async def play_audio(
    audio_b64: str = Body(..., embed=True),
    format: str = Body("wav", embed=True),
    device_index: Optional[int] = Body(None, embed=True),
    device_role: str = Body("output", embed=True),
):
    if format.lower() != "wav":
        raise HTTPException(status_code=400, detail="only wav is supported")
    if device_role not in ["output", "input"]:
        raise HTTPException(status_code=400, detail="invalid device_role")

    try:
        wav_bytes = base64.b64decode(audio_b64)
    except Exception as e:
        logger.error(f"[AudioRoutes] play_audio invalid audio_b64: {e}", exc_info=True)
        raise HTTPException(status_code=400, detail=f"invalid audio_b64: {e}")

    try:
        logger.info(
            f"[AudioRoutes] play_audio request: format={format}, role={device_role}, device_index={device_index}, bytes={len(wav_bytes)}"
        )
        used_device_index = device_index
        if device_role == "input":
            if device_index is not None:
                used_device_index = await asyncio.to_thread(
                    audio_service.resolve_output_device_index,
                    device_index,
                )
                if used_device_index is None:
                    raise HTTPException(
                        status_code=400,
                        detail="cannot_resolve_output_device",
                    )
        play_info = await asyncio.to_thread(audio_service.play_wav_bytes, wav_bytes, used_device_index)
        return {
            "status": "ok",
            "requested": {"device_index": device_index, "device_role": device_role, "format": format},
            "used": {"output_device_index": used_device_index},
            "play": play_info,
        }
    except HTTPException:
        raise
    except RuntimeError as e:
        logger.error(
            f"[AudioRoutes] play_audio runtime error: {e} (format={format}, role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(
            f"[AudioRoutes] play_audio value error: {e} (format={format}, role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            f"[AudioRoutes] play_audio unexpected error: {e} (format={format}, role={device_role}, device_index={device_index})",
            exc_info=True,
        )
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/convert/wav")
async def convert_to_wav(
    audio_b64: str = Body(..., embed=True),
    samplerate: Optional[int] = Body(None, embed=True),
    channels: Optional[int] = Body(None, embed=True),
):
    try:
        audio_bytes = base64.b64decode(audio_b64)
    except Exception as e:
        logger.error(f"[AudioRoutes] convert_to_wav invalid audio_b64: {e}", exc_info=True)
        raise HTTPException(status_code=400, detail=f"invalid audio_b64: {e}")

    try:
        logger.info(f"[AudioRoutes] convert_to_wav request: bytes={len(audio_bytes)}")
        wav_bytes = await audio_service.convert_to_wav(audio_bytes, samplerate=samplerate, channels=channels)
        return Response(content=wav_bytes, media_type="audio/wav")
    except RuntimeError as e:
        logger.error(f"[AudioRoutes] convert_to_wav runtime error: {e}", exc_info=True)
        if str(e) == "ffmpeg_not_found":
            raise HTTPException(
                status_code=500,
                detail="ffmpeg_not_found: 请安装 ffmpeg 并设置后端环境变量 FFMPEG_PATH（例如 C:\\\\path\\\\to\\\\ffmpeg.exe），用于音频格式转换兜底",
            )
        if str(e).startswith("ffmpeg_convert_failed"):
            raise HTTPException(status_code=500, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        logger.error(f"[AudioRoutes] convert_to_wav unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/loopback/transcribe")
async def loopback_transcribe(
    duration_seconds: float = Body(5.0, embed=True),
    device_index: Optional[int] = Body(None, embed=True),
    samplerate: int = Body(48000, embed=True),
    channels: int = Body(2, embed=True),
    model: str = Body("FunAudioLLM/SenseVoiceSmall", embed=True),
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    try:
        logger.info(
            f"[AudioRoutes] loopback_transcribe request: duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels}, model={model}, base_url={base_url}"
        )
        result = await asyncio.to_thread(
            audio_service.capture_loopback_wav_bytes_with_info,
            duration_seconds,
            device_index,
            samplerate,
            channels,
        )
        wav_bytes = result["wav_bytes"]
    except RuntimeError as e:
        logger.error(
            f"[AudioRoutes] loopback_transcribe capture runtime error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(
            f"[AudioRoutes] loopback_transcribe capture value error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            f"[AudioRoutes] loopback_transcribe capture unexpected error: {e} (duration={duration_seconds}, device_index={device_index}, sr={samplerate}, ch={channels})",
            exc_info=True,
        )
        raise HTTPException(status_code=500, detail=str(e))

    try:
        import time

        stt_start = time.time()
        text = await audio_service.transcribe(
            file_obj=wav_bytes,
            filename="loopback.wav",
            api_key=final_api_key,
            base_url=base_url,
            model=model,
        )
        stt_ms = int((time.time() - stt_start) * 1000)
        return {
            "status": "ok",
            "requested": {
                "duration_seconds": duration_seconds,
                "device_index": device_index,
                "samplerate": samplerate,
                "channels": channels,
                "model": model,
                "base_url": base_url,
            },
            "text": text,
            "text_len": len(text or ""),
            "stt_ms": stt_ms,
            "duration_seconds": duration_seconds,
            "used": result.get("used"),
        }
    except Exception as e:
        logger.error(f"[AudioRoutes] loopback_transcribe stt error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/speech/play")
async def tts_play(
    input: str = Body(..., embed=True),
    model: str = Body("FunAudioLLM/CosyVoice2-0.5B", embed=True),
    voice: Optional[str] = Body("alex", embed=True),
    speed: float = Body(1.0, embed=True),
    output_device_index: Optional[int] = Body(None, embed=True),
    device_index: Optional[int] = Body(None, embed=True),
    device_role: str = Body("output", embed=True),
    api_key: Optional[str] = Header(None, alias="X-SiliconFlow-Api-Key"),
    authorization: Optional[str] = Header(None, alias="Authorization"),
    base_url: Optional[str] = Header("https://api.siliconflow.cn/v1", alias="X-SiliconFlow-Base-Url"),
):
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")

    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    try:
        import time

        resolved_voice = _normalize_cosyvoice_voice(model, voice)
        logger.info(
            f"[AudioRoutes] tts_play request: model={model}, voice={voice}->{resolved_voice}, speed={speed}, output_device_index={output_device_index}, device_role={device_role}, device_index={device_index}, input_len={len(input)}"
        )
        gen_start = time.time()
        wav_bytes = await audio_service.generate_speech(
            text=input,
            api_key=final_api_key,
            base_url=base_url,
            model=model,
            voice=resolved_voice,
            response_format="wav",
            speed=speed,
        )
        gen_ms = int((time.time() - gen_start) * 1000)
    except Exception as e:
        logger.error(f"[AudioRoutes] tts_play generate error: {e}", exc_info=True)
        if str(e) == "ffmpeg_not_found":
            raise HTTPException(
                status_code=500,
                detail="ffmpeg_not_found: 请安装 ffmpeg 并设置后端环境变量 FFMPEG_PATH（例如 C:\\\\path\\\\to\\\\ffmpeg.exe），用于音频格式转换兜底",
            )
        if str(e).startswith("ffmpeg_convert_failed"):
            raise HTTPException(status_code=500, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))

    try:
        if device_role not in ["output", "input"]:
            raise HTTPException(status_code=400, detail="invalid device_role")

        used_device_index = output_device_index
        if used_device_index is None:
            used_device_index = device_index
        if device_role == "input" and used_device_index is not None:
            used_device_index = await asyncio.to_thread(
                audio_service.resolve_output_device_index,
                used_device_index,
            )
            if used_device_index is None:
                raise HTTPException(
                    status_code=400,
                    detail="cannot_resolve_output_device",
                )

        play_info = await asyncio.to_thread(audio_service.play_wav_bytes, wav_bytes, used_device_index)
        return {
            "status": "ok",
            "requested": {
                "model": model,
                "voice": voice,
                "voice_resolved": resolved_voice,
                "speed": speed,
                "output_device_index": output_device_index,
                "device_role": device_role,
                "device_index": device_index,
            },
            "generated": {"format": "wav", "bytes": len(wav_bytes), "gen_ms": gen_ms},
            "play": play_info,
            "used": {"output_device_index": used_device_index},
        }
    except RuntimeError as e:
        logger.error(f"[AudioRoutes] tts_play runtime error: {e}", exc_info=True)
        if str(e) in ["sounddevice_not_available", "platform_not_supported"]:
            raise HTTPException(status_code=503, detail=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    except ValueError as e:
        logger.error(f"[AudioRoutes] tts_play value error: {e}", exc_info=True)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"[AudioRoutes] tts_play unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

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
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")
    
    if not final_api_key:
        raise HTTPException(status_code=401, detail="API Key is required")

    # Read file content
    file_content = await file.read()
    
    try:
        logger.info(
            f"[AudioRoutes] transcribe_audio request: filename={file.filename}, bytes={len(file_content)}, model={model}, base_url={base_url}"
        )
        text = await audio_service.transcribe(
            file_obj=file_content,
            filename=file.filename,
            api_key=final_api_key,
            base_url=base_url,
            model=model
        )
        return {"text": text}
    except Exception as e:
        logger.error(f"[AudioRoutes] transcribe_audio error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/speech/stream")
async def generate_speech_stream(
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
    Generate speech from text (TTS) with streaming.
    Returns audio binary stream.
    """
    final_api_key = api_key
    if not final_api_key and authorization and authorization.startswith("Bearer "):
        final_api_key = authorization.replace("Bearer ", "")
        
    if not final_api_key:
        logger.error("[AudioRoutes] generate_speech_stream missing API key")
        raise HTTPException(status_code=401, detail="API Key is required")

    resolved_voice = _normalize_cosyvoice_voice(model, voice)

    logger.info(
        f"[AudioRoutes] generate_speech_stream request: model={model}, voice={voice}->{resolved_voice}, speed={speed}, response_format={response_format}, input_len={len(input)}"
    )

    async def iterfile():
        try:
            async for chunk in audio_service.generate_speech_stream(
                text=input,
                api_key=final_api_key,
                base_url=base_url,
                model=model,
                voice=resolved_voice,
                response_format=response_format,
                speed=speed
            ):
                yield chunk
        except Exception as e:
            logger.error(f"[AudioRoutes] generate_speech_stream error: {e}", exc_info=True)

    media_type = f"audio/{response_format}"
    return StreamingResponse(iterfile(), media_type=media_type)

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
        
    if not final_api_key:
        logger.error("[AudioRoutes] generate_speech missing API key")
        raise HTTPException(status_code=401, detail="API Key is required")

    original_voice = voice
    original_model = model
    voice = _normalize_cosyvoice_voice(model, voice)
    
    import time
    start_time = time.time()
    logger.info(
        f"[AudioRoutes] generate_speech request: model={original_model}->{model}, voice={original_voice}->{voice}, speed={speed}, response_format={response_format}, input_len={len(input)}"
    )

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
        
        duration = time.time() - start_time
        logger.info(f"[AudioRoutes] generate_speech finished: seconds={duration:.2f}, bytes={len(audio_content)}")

        media_type = f"audio/{response_format}"
        return Response(content=audio_content, media_type=media_type)
    except Exception as e:
        duration = time.time() - start_time
        logger.error(f"[AudioRoutes] generate_speech error: {e} (seconds={duration:.2f})", exc_info=True)
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
