import httpx
import openai
from fastapi import UploadFile
from typing import Optional, List, Dict, Any
import json
from app.core.config import settings

class AudioService:
    def __init__(self):
        pass

    def _get_client(self, api_key: str, base_url: str) -> openai.AsyncOpenAI:
        return openai.AsyncOpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=60.0
        )

    async def transcribe(self, 
                         file_obj: Any, 
                         filename: str,
                         api_key: str, 
                         base_url: str, 
                         model: str = "FunAudioLLM/SenseVoiceSmall") -> str:
        """
        Transcribe audio using OpenAI-compatible API (STT).
        """
        client = self._get_client(api_key, base_url)
        
        # OpenAI client expects a tuple (filename, file_content, content_type) or just file path
        # Since we receive UploadFile or bytes, we need to handle it.
        # If file_obj is bytes, we wrap it.
        
        try:
            transcript = await client.audio.transcriptions.create(
                model=model,
                file=(filename, file_obj)
            )
            return transcript.text
        except openai.APIStatusError as e:
            print(f"[AudioService] STT API Error: {e.status_code} - {e.response.text}")
            raise e
        except Exception as e:
            print(f"[AudioService] STT Error: {e}")
            raise e
        finally:
            await client.close()

    async def generate_speech(self, 
                              text: str, 
                              api_key: str, 
                              base_url: str, 
                              model: str = "FunAudioLLM/CosyVoice2-0.5B",
                              voice: Optional[str] = "alex", # Default voice or specific voice ID
                              response_format: str = "mp3",
                              speed: float = 1.0) -> bytes:
        """
        Generate speech using OpenAI-compatible API (TTS).
        """
        import time
        start_time = time.time()
        client = self._get_client(api_key, base_url)

        # Auto-fix common voice aliases for SiliconFlow/CosyVoice
        if model and "CosyVoice" in model:
            if not voice or voice == "alex":
                voice = "FunAudioLLM/CosyVoice2-0.5B:alex"
            elif voice == "sys_female_01": 
                voice = "FunAudioLLM/CosyVoice2-0.5B:alex" 
            elif voice == "sys_male_01":
                voice = "FunAudioLLM/CosyVoice2-0.5B:benjamin"
            elif ":" not in voice and "/" not in voice:
                 known_system_voices = ["alex", "anna", "bella", "benjamin", "charles", "diana"]
                 if voice in known_system_voices:
                     voice = f"{model}:{voice}"
        
        print(f"[AudioService] Calling TTS API: {base_url}/audio/speech")
        print(f"[AudioService] Params: model={model}, voice={voice}, speed={speed}, input_len={len(text)}")

        try:
            # Note: SiliconFlow might use 'voice' parameter for voice style ID
            response = await client.audio.speech.create(
                model=model,
                voice=voice,
                input=text,
                response_format=response_format,
                speed=speed
            )
            duration = time.time() - start_time
            print(f"[AudioService] TTS API Completed in {duration:.2f}s. Size: {len(response.content)} bytes")
            audio_bytes = response.content
            if str(response_format).lower() == "wav" and not self._is_wav_bytes(audio_bytes):
                print("[AudioService] TTS returned non-wav bytes, converting to wav via ffmpeg")
                audio_bytes = await self._convert_audio_bytes_to_wav(audio_bytes)
            return audio_bytes
        except openai.APIStatusError as e:
            duration = time.time() - start_time
            print(f"[AudioService] TTS API Error after {duration:.2f}s: {e.status_code} - {e.response.text}")
            raise e
        except Exception as e:
            duration = time.time() - start_time
            print(f"[AudioService] TTS Error after {duration:.2f}s: {e}")
            raise e
        finally:
            await client.close()

    def _is_wav_bytes(self, audio_bytes: bytes) -> bool:
        if not isinstance(audio_bytes, (bytes, bytearray)):
            return False
        if len(audio_bytes) < 12:
            return False
        return audio_bytes[0:4] == b"RIFF" and audio_bytes[8:12] == b"WAVE"

    def _resolve_ffmpeg_path(self) -> str:
        import os
        from pathlib import Path

        configured = (getattr(settings, "FFMPEG_PATH", None) or "").strip()
        if configured:
            return configured

        if os.name == "nt":
            backend_dir = Path(__file__).resolve().parents[2]
            root = backend_dir / "third_party" / "ffmpeg"
            candidate = root / "bin" / "ffmpeg.exe"
            if candidate.exists():
                return str(candidate)
            if root.exists():
                for found in root.rglob("ffmpeg.exe"):
                    if found.exists():
                        return str(found)

        return "ffmpeg"

    async def _convert_audio_bytes_to_wav(self, audio_bytes: bytes) -> bytes:
        import asyncio

        return await asyncio.to_thread(self._convert_audio_bytes_to_wav_blocking, audio_bytes)

    async def convert_to_wav(self, audio_bytes: bytes) -> bytes:
        if self._is_wav_bytes(audio_bytes):
            return audio_bytes
        return await self._convert_audio_bytes_to_wav(audio_bytes)

    def _convert_audio_bytes_to_wav_blocking(self, audio_bytes: bytes) -> bytes:
        import subprocess

        ffmpeg_path = self._resolve_ffmpeg_path()
        cmd = [
            ffmpeg_path,
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            "pipe:0",
            "-f",
            "wav",
            "-acodec",
            "pcm_s16le",
            "pipe:1",
        ]
        try:
            proc = subprocess.run(
                cmd,
                input=audio_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        except FileNotFoundError as e:
            raise RuntimeError("ffmpeg_not_found") from e

        if proc.returncode != 0:
            stderr = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"ffmpeg_convert_failed: {stderr}")
        out = proc.stdout or b""
        if not self._is_wav_bytes(out):
            raise RuntimeError("ffmpeg_convert_failed: output_not_wav")
        return out

    async def generate_speech_stream(self, 
                              text: str, 
                              api_key: str, 
                              base_url: str, 
                              model: str = "FunAudioLLM/CosyVoice2-0.5B",
                              voice: Optional[str] = "alex",
                              response_format: str = "mp3",
                              speed: float = 1.0):
        """
        Generate speech using OpenAI-compatible API (TTS) with streaming.
        Yields bytes chunks.
        """
        import time
        start_time = time.time()
        client = self._get_client(api_key, base_url)
        
        # Auto-fix common voice aliases for SiliconFlow/CosyVoice
        if model and "CosyVoice" in model:
            if not voice or voice == "alex":
                voice = "FunAudioLLM/CosyVoice2-0.5B:alex"
            elif voice == "sys_female_01": 
                voice = "FunAudioLLM/CosyVoice2-0.5B:alex" 
            elif voice == "sys_male_01":
                voice = "FunAudioLLM/CosyVoice2-0.5B:benjamin"
            elif ":" not in voice and "/" not in voice:
                 known_system_voices = ["alex", "anna", "bella", "benjamin", "charles", "diana"]
                 if voice in known_system_voices:
                     voice = f"{model}:{voice}"

        print(f"[AudioService] Calling TTS API (Stream): {base_url}/audio/speech")
        
        try:
            # Use with_streaming_response to get a streamable response
            async with client.audio.speech.with_streaming_response.create(
                model=model,
                voice=voice,
                input=text,
                response_format=response_format,
                speed=speed
            ) as response:
                first_chunk_time = time.time() - start_time
                print(f"[AudioService] TTS Stream First Chunk in {first_chunk_time:.2f}s")
                
                async for chunk in response.iter_bytes(chunk_size=4096):
                    yield chunk
                    
            total_time = time.time() - start_time
            print(f"[AudioService] TTS Stream Completed in {total_time:.2f}s")
            
        except Exception as e:
            print(f"[AudioService] TTS Stream Error: {e}")
            raise e
        finally:
            await client.close()

    # --- SiliconFlow Specific Custom Endpoints ---

    async def upload_voice(self, 
                           file_path: str, 
                           custom_name: str,
                           text: Optional[str], 
                           api_key: str, 
                           base_url: str) -> Dict[str, Any]:
        """
        Upload a reference audio for voice cloning (SiliconFlow specific).
        POST /v1/uploads/audio/voice
        """
        # SiliconFlow API Spec: https://docs.siliconflow.cn/cn/api-reference/audio/upload-voice
        # URL: https://api.siliconflow.cn/v1/uploads/audio/voice
        
        # Strip trailing slash if present
        base_url = base_url.rstrip("/")
        url = f"{base_url}/uploads/audio/voice"
            
        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        # Spec says:
        # customName: string (required)
        # text: string (optional)
        # file: file (required)
        
        data = {"customName": custom_name}
        if text:
            data["text"] = text
            
        files = {
            "file": open(file_path, "rb")
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(url, headers=headers, data=data, files=files, timeout=60.0)
            # Log error details if failed
            if not response.is_success:
                print(f"[AudioService] Upload Voice Error: {response.status_code} - {response.text}")
            response.raise_for_status()
            return response.json()

    async def get_voices(self, api_key: str, base_url: str) -> List[Dict[str, Any]]:
        """
        Get list of uploaded voices (SiliconFlow specific).
        GET /v1/audio/voice/list
        """
        base_url = base_url.rstrip("/")
        url = f"{base_url}/audio/voice/list"
            
        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=headers, timeout=30.0)
            if not response.is_success:
                print(f"[AudioService] Get Voices Error: {response.status_code} - {response.text}")
            response.raise_for_status()
            data = response.json()
            # Spec says response is like:
            # { "results": [ { "voiceId": "...", "customName": "...", ... } ], ... }
            return data.get("results", []) if isinstance(data, dict) else data

    async def delete_voice(self, voice_id: str, api_key: str, base_url: str) -> Dict[str, Any]:
        """
        Delete a voice (SiliconFlow specific).
        DELETE /v1/audio/voice/{voiceId}
        """
        # Spec: https://docs.siliconflow.cn/cn/api-reference/audio/delete-voice
        # DELETE /v1/audio/voice/{voiceId}
        
        base_url = base_url.rstrip("/")
        url = f"{base_url}/audio/voice/{voice_id}"

        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.delete(url, headers=headers, timeout=30.0)
            if not response.is_success:
                print(f"[AudioService] Delete Voice Error: {response.status_code} - {response.text}")
            response.raise_for_status()
            return response.json()

    def _require_sounddevice(self):
        try:
            import sounddevice as sd
            return sd
        except Exception as e:
            raise RuntimeError("sounddevice_not_available") from e

    def list_audio_devices(self) -> Dict[str, Any]:
        import platform

        if platform.system() != "Windows":
            raise RuntimeError("platform_not_supported")

        sd = self._require_sounddevice()

        def to_jsonable(v):
            if isinstance(v, (str, bool)) or v is None:
                return v
            if isinstance(v, (int, float)):
                return v
            if isinstance(v, dict):
                return {str(k): to_jsonable(val) for k, val in v.items()}
            if isinstance(v, (list, tuple)):
                return [to_jsonable(x) for x in v]
            return str(v)

        devices = [to_jsonable(dict(d)) for d in sd.query_devices()]
        hostapis = [to_jsonable(dict(h)) for h in sd.query_hostapis()]
        default_in, default_out = sd.default.device

        return {
            "default": {"input": default_in, "output": default_out},
            "hostapis": hostapis,
            "devices": devices,
        }

    def _wasapi_loopback_supported(self, sd) -> bool:
        try:
            import inspect

            sig = inspect.signature(sd.WasapiSettings)
            return "loopback" in sig.parameters
        except Exception:
            return False

    def resolve_input_device_index_for_output(self, device_index: Optional[int]) -> Optional[int]:
        if device_index is None:
            return None

        import re
        from difflib import SequenceMatcher

        sd = self._require_sounddevice()
        devices = sd.query_devices()
        if device_index < 0 or device_index >= len(devices):
            return None

        src = dict(devices[device_index])
        src_max_in = int(src.get("max_input_channels") or 0)
        if src_max_in > 0:
            return device_index

        src_name = str(src.get("name") or "").strip()
        if not src_name:
            return None

        src_hostapi = src.get("hostapi")
        src_lower = src_name.lower()

        def _expected_input_name(s: str) -> str:
            s = s.lower()
            s = s.replace("cable in", "cable out")
            s = s.replace("cable input", "cable output")
            s = s.replace("voicemeeter input", "voicemeeter output")
            s = s.replace("input", "output")
            s = s.replace("播放", "录音")
            return s

        def _base_norm(s: str) -> str:
            s = s.lower()
            s = re.sub(r"\(.*?\)", "", s)
            s = s.replace("cable in", "cable")
            s = s.replace("cable out", "cable")
            s = s.replace("cable input", "cable")
            s = s.replace("cable output", "cable")
            s = s.replace("voicemeeter input", "voicemeeter")
            s = s.replace("voicemeeter output", "voicemeeter")
            s = s.replace("input", "")
            s = s.replace("output", "")
            s = s.replace("播放", "")
            s = s.replace("录音", "")
            s = re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "", s)
            return s

        expected = _expected_input_name(src_lower)
        expected_base = _base_norm(expected)

        best_idx: Optional[int] = None
        best_score = 0.0

        for idx, dev in enumerate(devices):
            d = dict(dev)
            max_in = int(d.get("max_input_channels") or 0)
            if max_in <= 0:
                continue
            name = str(d.get("name") or "").strip()
            if not name:
                continue
            lower = name.lower()

            score = 0.0
            if expected and expected in lower:
                score += 2.0

            score += SequenceMatcher(None, expected, lower).ratio()
            score += 1.5 * SequenceMatcher(None, expected_base, _base_norm(lower)).ratio()

            if src_hostapi is not None and d.get("hostapi") == src_hostapi:
                score += 0.3

            if score > best_score:
                best_score = score
                best_idx = idx

        if best_idx is None:
            return None
        if best_score < 1.2:
            return None
        return best_idx

    def capture_loopback_wav_bytes_with_info(
        self,
        duration_seconds: float,
        device_index: Optional[int] = None,
        samplerate: int = 48000,
        channels: int = 2,
        dtype: str = "int16",
    ) -> Dict[str, Any]:
        import io
        import time
        import wave

        sd = self._require_sounddevice()

        if duration_seconds <= 0:
            raise ValueError("duration_seconds must be > 0")
        if duration_seconds > 30:
            raise ValueError("duration_seconds too large")
        if channels <= 0 or channels > 8:
            raise ValueError("invalid channels")
        if dtype != "int16":
            raise ValueError("only int16 is supported")

        requested_device_index = device_index
        if requested_device_index is None:
            try:
                _, default_out = sd.default.device
                if isinstance(default_out, (int, float)) and int(default_out) >= 0:
                    requested_device_index = int(default_out)
            except Exception:
                requested_device_index = None

        devices = None
        try:
            devices = sd.query_devices()
        except Exception:
            devices = None

        def _device_default_sr(idx: Optional[int]) -> Optional[int]:
            if idx is None:
                return None
            try:
                if devices is None:
                    return None
                if idx < 0 or idx >= len(devices):
                    return None
                d = dict(devices[idx])
                sr = d.get("default_samplerate")
                sr = int(sr) if isinstance(sr, (int, float)) else None
                return sr if sr and sr > 0 else None
            except Exception:
                return None

        extra_settings = None
        capture_mode = None
        capture_device_index = None

        if self._wasapi_loopback_supported(sd):
            if requested_device_index is None:
                raise RuntimeError("loopback_not_supported")
            extra_settings = sd.WasapiSettings(loopback=True)
            capture_mode = "wasapi_loopback"
            capture_device_index = requested_device_index
        else:
            if requested_device_index is None:
                raise RuntimeError("loopback_not_supported")
            capture_device_index = self.resolve_input_device_index_for_output(requested_device_index)
            if capture_device_index is None:
                raise RuntimeError("loopback_not_supported")
            capture_mode = "input_device"

        chunks: List[bytes] = []

        def callback(indata, frames, time_info, status):
            if indata:
                chunks.append(bytes(indata))

        used_samplerate = int(samplerate)
        try:
            stream_kwargs = {
                "samplerate": used_samplerate,
                "channels": channels,
                "dtype": dtype,
                "device": capture_device_index,
                "callback": callback,
            }
            if extra_settings is not None:
                stream_kwargs["extra_settings"] = extra_settings
            with sd.RawInputStream(**stream_kwargs):
                sd.sleep(int(duration_seconds * 1000))
        except Exception:
            fallback_sr = _device_default_sr(capture_device_index)
            if fallback_sr and fallback_sr != used_samplerate:
                used_samplerate = int(fallback_sr)
                chunks = []
                stream_kwargs = {
                    "samplerate": used_samplerate,
                    "channels": channels,
                    "dtype": dtype,
                    "device": capture_device_index,
                    "callback": callback,
                }
                if extra_settings is not None:
                    stream_kwargs["extra_settings"] = extra_settings
                with sd.RawInputStream(**stream_kwargs):
                    sd.sleep(int(duration_seconds * 1000))
            else:
                raise

        raw_audio = b"".join(chunks)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(2)
            wf.setframerate(used_samplerate)
            wf.writeframes(raw_audio)

        capture_device_name = None
        try:
            if devices is not None and 0 <= int(capture_device_index) < len(devices):
                capture_device_name = str(dict(devices[int(capture_device_index)]).get("name") or "")
        except Exception:
            capture_device_name = None

        return {
            "wav_bytes": buf.getvalue(),
            "requested": {"device_index": requested_device_index},
            "used": {
                "device_index": capture_device_index,
                "samplerate": used_samplerate,
                "channels": channels,
                "dtype": dtype,
                "mode": capture_mode,
                "device_name": capture_device_name,
            },
        }

    def capture_loopback_wav_bytes(
        self,
        duration_seconds: float,
        device_index: Optional[int] = None,
        samplerate: int = 48000,
        channels: int = 2,
        dtype: str = "int16",
    ) -> bytes:
        result = self.capture_loopback_wav_bytes_with_info(
            duration_seconds=duration_seconds,
            device_index=device_index,
            samplerate=samplerate,
            channels=channels,
            dtype=dtype,
        )
        return result["wav_bytes"]

    def measure_loopback_level(
        self,
        duration_seconds: float,
        device_index: Optional[int] = None,
        samplerate: int = 48000,
        channels: int = 2,
        dtype: str = "int16",
    ) -> Dict[str, Any]:
        import audioop
        import time

        sd = self._require_sounddevice()
        requested_device_index = device_index
        if requested_device_index is None:
            try:
                _, default_out = sd.default.device
                if isinstance(default_out, (int, float)) and int(default_out) >= 0:
                    requested_device_index = int(default_out)
            except Exception:
                requested_device_index = None

        devices = sd.query_devices()
        hostapis = sd.query_hostapis()

        extra_settings = None
        capture_mode = None
        capture_device_index = None

        if self._wasapi_loopback_supported(sd):
            if requested_device_index is None:
                raise RuntimeError("loopback_not_supported")
            extra_settings = sd.WasapiSettings(loopback=True)
            capture_mode = "wasapi_loopback"
            capture_device_index = requested_device_index
        else:
            if requested_device_index is None:
                raise RuntimeError("loopback_not_supported")
            capture_device_index = self.resolve_input_device_index_for_output(requested_device_index)
            if capture_device_index is None:
                raise RuntimeError("loopback_not_supported")
            capture_mode = "input_device"

        dev_info = None
        if capture_device_index is not None and 0 <= int(capture_device_index) < len(devices):
            dev_info = dict(devices[int(capture_device_index)])

        def _device_default_sr(idx: Optional[int]) -> Optional[int]:
            if idx is None:
                return None
            try:
                if idx < 0 or idx >= len(devices):
                    return None
                d = dict(devices[idx])
                sr = d.get("default_samplerate")
                sr = int(sr) if isinstance(sr, (int, float)) else None
                return sr if sr and sr > 0 else None
            except Exception:
                return None

        chunks: List[bytes] = []

        def callback(indata, frames, time_info, status):
            if indata:
                chunks.append(bytes(indata))

        used_samplerate = int(samplerate)
        started_at = time.time()
        try:
            stream_kwargs = {
                "samplerate": used_samplerate,
                "channels": channels,
                "dtype": dtype,
                "device": capture_device_index,
                "callback": callback,
            }
            if extra_settings is not None:
                stream_kwargs["extra_settings"] = extra_settings
            with sd.RawInputStream(**stream_kwargs):
                sd.sleep(int(duration_seconds * 1000))
        except Exception:
            fallback_sr = _device_default_sr(int(capture_device_index) if capture_device_index is not None else None)
            if fallback_sr and fallback_sr != used_samplerate:
                used_samplerate = int(fallback_sr)
                chunks = []
                stream_kwargs = {
                    "samplerate": used_samplerate,
                    "channels": channels,
                    "dtype": dtype,
                    "device": capture_device_index,
                    "callback": callback,
                }
                if extra_settings is not None:
                    stream_kwargs["extra_settings"] = extra_settings
                with sd.RawInputStream(**stream_kwargs):
                    sd.sleep(int(duration_seconds * 1000))
            else:
                raise

        raw_audio = b"".join(chunks)
        elapsed_ms = int((time.time() - started_at) * 1000)

        rms = audioop.rms(raw_audio, 2) if raw_audio else 0
        peak = audioop.max(raw_audio, 2) if raw_audio else 0

        hostapi_name = None
        try:
            if dev_info and dev_info.get("hostapi") is not None:
                hi = int(dev_info.get("hostapi"))
                if 0 <= hi < len(hostapis):
                    hostapi_name = str(dict(hostapis[hi]).get("name") or "")
        except Exception:
            hostapi_name = None

        return {
            "requested": {"device_index": requested_device_index},
            "used": {
                "device_index": int(capture_device_index) if capture_device_index is not None else None,
                "samplerate": used_samplerate,
                "channels": channels,
                "dtype": dtype,
                "elapsed_ms": elapsed_ms,
                "mode": capture_mode,
            },
            "level": {
                "rms": int(rms),
                "peak": int(peak),
                "is_silent": bool(peak == 0 and rms == 0),
                "bytes": len(raw_audio),
            },
            "device": {
                "name": (str(dev_info.get("name")) if dev_info else None),
                "hostapi": (int(dev_info.get("hostapi")) if dev_info and dev_info.get("hostapi") is not None else None),
                "hostapi_name": hostapi_name,
                "default_samplerate": (int(dev_info.get("default_samplerate")) if dev_info and isinstance(dev_info.get("default_samplerate"), (int, float)) else None),
                "max_input_channels": (int(dev_info.get("max_input_channels")) if dev_info and isinstance(dev_info.get("max_input_channels"), (int, float)) else None),
                "max_output_channels": (int(dev_info.get("max_output_channels")) if dev_info and isinstance(dev_info.get("max_output_channels"), (int, float)) else None),
            },
        }

    def generate_test_tone_wav_bytes(
        self,
        frequency_hz: float = 880.0,
        duration_seconds: float = 0.6,
        samplerate: int = 48000,
        channels: int = 2,
        amplitude: float = 0.15,
    ) -> bytes:
        import io
        import math
        import struct
        import wave

        sr = int(samplerate)
        ch = int(channels)
        if sr <= 0:
            raise ValueError("invalid samplerate")
        if ch <= 0 or ch > 8:
            raise ValueError("invalid channels")
        if duration_seconds <= 0 or duration_seconds > 5:
            raise ValueError("invalid duration_seconds")

        amp = float(amplitude)
        if amp <= 0:
            amp = 0.05
        if amp > 0.95:
            amp = 0.95

        total_frames = int(sr * float(duration_seconds))
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(ch)
            wf.setsampwidth(2)
            wf.setframerate(sr)
            frames = bytearray()
            for i in range(total_frames):
                t = i / sr
                v = math.sin(2.0 * math.pi * float(frequency_hz) * t)
                s = int(max(-1.0, min(1.0, v * amp)) * 32767)
                packed = struct.pack("<h", s)
                frames.extend(packed * ch)
            wf.writeframes(bytes(frames))
        return buf.getvalue()

    def play_wav_bytes(self, wav_bytes: bytes, device_index: Optional[int] = None) -> Dict[str, Any]:
        import io
        import wave
        import audioop

        sd = self._require_sounddevice()

        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            channels = wf.getnchannels()
            samplerate = wf.getframerate()
            sampwidth = wf.getsampwidth()
            frame_count = wf.getnframes()
            audio_data = wf.readframes(frame_count)

        def _try_play(raw_bytes: bytes, sr: int, ch: int) -> None:
            with sd.RawOutputStream(
                samplerate=sr,
                channels=ch,
                dtype="int16",
                device=device_index,
            ) as stream:
                stream.write(raw_bytes)

        try:
            if sampwidth != 2:
                raise ValueError("only 16-bit PCM wav is supported")
            _try_play(audio_data, samplerate, channels)
            used_sr = samplerate
            used_ch = channels
            converted = False
            target_sr = samplerate
            target_ch = channels
        except Exception:
            data16 = audio_data
            width = int(sampwidth)
            if width != 2:
                data16 = audioop.lin2lin(data16, width, 2)

            target_sr = int(samplerate)
            target_ch = int(channels)
            try:
                if device_index is not None:
                    dev = sd.query_devices(device_index)
                    dev_sr = dev.get("default_samplerate")
                    dev_sr = int(dev_sr) if isinstance(dev_sr, (int, float)) else 0
                    if dev_sr > 0:
                        target_sr = dev_sr
                    max_out = int(dev.get("max_output_channels") or 0)
                    if max_out > 0:
                        target_ch = min(max_out, 2)
                        if target_ch <= 0:
                            target_ch = channels
            except Exception:
                target_sr = int(samplerate)
                target_ch = int(channels)

            if channels != target_ch:
                if channels == 1 and target_ch == 2:
                    data16 = audioop.tostereo(data16, 2, 1.0, 1.0)
                elif channels == 2 and target_ch == 1:
                    data16 = audioop.tomono(data16, 2, 0.5, 0.5)
                else:
                    target_ch = int(channels)

            if samplerate != target_sr:
                data16, _ = audioop.ratecv(data16, 2, target_ch, int(samplerate), int(target_sr), None)

            _try_play(data16, int(target_sr), int(target_ch))
            used_sr = int(target_sr)
            used_ch = int(target_ch)
            converted = True

        return {
            "device_index": device_index,
            "samplerate": used_sr,
            "channels": used_ch,
            "frames": frame_count,
            "bytes": len(audio_data),
            "source": {"samplerate": samplerate, "channels": channels, "sampwidth": sampwidth},
            "target": {"samplerate": int(target_sr), "channels": int(target_ch)},
            "converted": converted,
        }

    def resolve_output_device_index(self, device_index: Optional[int]) -> Optional[int]:
        if device_index is None:
            return None

        import re
        from difflib import SequenceMatcher

        sd = self._require_sounddevice()
        devices = sd.query_devices()
        if device_index < 0 or device_index >= len(devices):
            return None

        src = dict(devices[device_index])
        src_max_out = int(src.get("max_output_channels") or 0)
        if src_max_out > 0:
            return device_index

        src_name = str(src.get("name") or "").strip()
        if not src_name:
            return None

        src_hostapi = src.get("hostapi")
        src_lower = src_name.lower()

        def _expected_output_name(s: str) -> str:
            s = s.lower()
            s = s.replace("cable output", "cable input")
            s = s.replace("voicemeeter output", "voicemeeter input")
            s = s.replace("output", "input")
            s = s.replace("录音", "播放")
            return s

        def _base_norm(s: str) -> str:
            s = s.lower()
            s = re.sub(r"\(.*?\)", "", s)
            s = s.replace("cable input", "cable")
            s = s.replace("cable output", "cable")
            s = s.replace("voicemeeter input", "voicemeeter")
            s = s.replace("voicemeeter output", "voicemeeter")
            s = s.replace("input", "")
            s = s.replace("output", "")
            s = s.replace("播放", "")
            s = s.replace("录音", "")
            s = re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "", s)
            return s

        expected = _expected_output_name(src_lower)
        expected_base = _base_norm(expected)

        best_idx: Optional[int] = None
        best_score = 0.0

        for idx, dev in enumerate(devices):
            d = dict(dev)
            max_out = int(d.get("max_output_channels") or 0)
            if max_out <= 0:
                continue
            name = str(d.get("name") or "").strip()
            if not name:
                continue
            lower = name.lower()

            score = 0.0
            if expected and expected in lower:
                score += 2.0

            score += SequenceMatcher(None, expected, lower).ratio()
            score += 1.5 * SequenceMatcher(None, expected_base, _base_norm(lower)).ratio()

            if src_hostapi is not None and d.get("hostapi") == src_hostapi:
                score += 0.3

            if score > best_score:
                best_score = score
                best_idx = idx

        if best_idx is None:
            return None
        if best_score < 1.2:
            return None
        return best_idx
