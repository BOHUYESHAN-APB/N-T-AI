import os
from pydantic_settings import BaseSettings
if os.environ.get("USE_HTTPS", "").strip() == "":
    os.environ["USE_HTTPS"] = "false"


class Settings(BaseSettings):
    PROJECT_NAME: str = "Astra-Me (Fire-fly)"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str = "sqlite:///./astra_me_v3.db"
    SQL_ECHO: bool = False
    KNOW_TIMES_BATCH_SIZE: int = 10

    # LLM Configuration
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = "https://api.openai.com/v1"
    LLM_MODEL: str = "gpt-3.5-turbo"

    # TTS Configuration (SiliconFlow)
    TTS_API_KEY: str = ""
    TTS_BASE_URL: str = "https://api.siliconflow.cn/v1"

    # STT Configuration (OpenAI-compatible)
    STT_API_KEY: str = ""
    STT_BASE_URL: str = ""
    STT_MODEL: str = "FunAudioLLM/SenseVoiceSmall"

    FFMPEG_PATH: str = ""

    VECTOR_MEMORY_BACKEND: str = "sqlite"
    VECTOR_MEMORY_HTTP_URL: str = ""

    KNOWLEDGE_BACKEND: str = ""
    KNOWLEDGE_HTTP_URL: str = ""

    PERSONA_STYLE: str = "neuro"
    PROACTIVE_IDLE_ENABLED: bool = True
    PROACTIVE_IDLE_MIN_SEC: int = 45

    LOG_MAX_ERRORS: int = 5

    # Server / HTTPS
    HOST: str = "0.0.0.0"
    PORT: int = 23456
    USE_HTTPS: bool = False
    SSL_CERT_PATH: str = "./certs/cert.pem"
    SSL_KEY_PATH: str = "./certs/key.pem"

    # Plugins
    BILIBILI_ROOM_ID: int = 0 # 0 means disabled/not configured

    class Config:
        env_file = ".env"


settings = Settings()
