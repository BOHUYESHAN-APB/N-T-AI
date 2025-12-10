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
        client = self._get_client(api_key, base_url)
        
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
            return response.content
        except openai.APIStatusError as e:
            print(f"[AudioService] TTS API Error: {e.status_code} - {e.response.text}")
            raise e
        except Exception as e:
            print(f"[AudioService] TTS Error: {e}")
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
        # Ensure base_url doesn't end with /v1 if we are appending /v1... 
        # Usually base_url is "https://api.siliconflow.cn/v1"
        # We need to construct the URL carefully.
        
        # If base_url ends with /v1, we strip it to avoid duplication if needed, 
        # OR we assume base_url is the root. 
        # OpenAI client usually takes ".../v1".
        # SiliconFlow docs: https://api.siliconflow.cn/v1/uploads/audio/voice
        
        url = f"{base_url}/uploads/audio/voice"
        if base_url.endswith("/"):
            url = f"{base_url}uploads/audio/voice"
            
        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        data = {"customName": custom_name}
        if text:
            data["text"] = text
            
        files = {
            "file": open(file_path, "rb")
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(url, headers=headers, data=data, files=files, timeout=60.0)
            response.raise_for_status()
            return response.json()

    async def get_voices(self, api_key: str, base_url: str) -> List[Dict[str, Any]]:
        """
        Get list of uploaded voices (SiliconFlow specific).
        GET /v1/audio/voice/list
        """
        url = f"{base_url}/audio/voice/list"
        if base_url.endswith("/"):
            url = f"{base_url}audio/voice/list"
            
        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.get(url, headers=headers, timeout=30.0)
            response.raise_for_status()
            data = response.json()
            # Format might be {"results": [...]} or just [...]
            return data.get("results", []) if isinstance(data, dict) else data

    async def delete_voice(self, voice_id: str, api_key: str, base_url: str) -> Dict[str, Any]:
        """
        Delete a voice (SiliconFlow specific).
        DELETE /v1/audio/voice/{voiceId}
        """
        # Note: Check docs for exact path. 
        # Docs say: DELETE /v1/audio/voice
        # Body: {"voiceId": "..."} ? Or path param?
        # User provided: https://docs.siliconflow.cn/cn/api-reference/audio/delete-voice
        # Let's assume it follows standard REST or check if I can find more info.
        # Usually DELETE takes ID in path or body.
        # Let's assume body based on some APIs, or path. 
        # Wait, I'll use a safe bet: try to find the exact spec.
        # Since I can't browse, I will assume it's likely `DELETE /v1/audio/voice/{voiceId}` or `DELETE /v1/audio/voice` with body.
        # I will implement it as `DELETE /v1/audio/voice/{voiceId}` for now as it's most common.
        
        url = f"{base_url}/audio/voice/{voice_id}"
        if base_url.endswith("/"):
             url = f"{base_url}audio/voice/{voice_id}"

        headers = {
            "Authorization": f"Bearer {api_key}"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.delete(url, headers=headers, timeout=30.0)
            response.raise_for_status()
            return response.json()
