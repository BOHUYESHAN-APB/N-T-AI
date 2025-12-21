import httpx
import openai
from fastapi import UploadFile
from typing import Optional, List, Dict, Any
import json

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
            return response.content
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

    def capture_loopback_wav_bytes(
        self,
        duration_seconds: float,
        device_index: Optional[int] = None,
        samplerate: int = 48000,
        channels: int = 2,
        dtype: str = "int16",
    ) -> bytes:
        import io
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

        extra = sd.WasapiSettings(loopback=True)
        chunks: List[bytes] = []

        def callback(indata, frames, time, status):
            if indata:
                chunks.append(bytes(indata))

        with sd.RawInputStream(
            samplerate=samplerate,
            channels=channels,
            dtype=dtype,
            device=device_index,
            extra_settings=extra,
            callback=callback,
        ):
            sd.sleep(int(duration_seconds * 1000))

        raw_audio = b"".join(chunks)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(channels)
            wf.setsampwidth(2)
            wf.setframerate(samplerate)
            wf.writeframes(raw_audio)
        return buf.getvalue()

    def play_wav_bytes(self, wav_bytes: bytes, device_index: Optional[int] = None) -> Dict[str, Any]:
        import io
        import wave

        sd = self._require_sounddevice()

        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            channels = wf.getnchannels()
            samplerate = wf.getframerate()
            sampwidth = wf.getsampwidth()
            frame_count = wf.getnframes()
            audio_data = wf.readframes(frame_count)

        if sampwidth != 2:
            raise ValueError("only 16-bit PCM wav is supported")

        with sd.RawOutputStream(
            samplerate=samplerate,
            channels=channels,
            dtype="int16",
            device=device_index,
        ) as stream:
            stream.write(audio_data)

        return {
            "samplerate": samplerate,
            "channels": channels,
            "frames": frame_count,
            "bytes": len(audio_data),
        }
