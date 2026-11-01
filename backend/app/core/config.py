import os
from pathlib import Path
from pydantic_settings import BaseSettings
if os.environ.get("USE_HTTPS", "").strip() == "":
    os.environ["USE_HTTPS"] = "false"

BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
DEFAULT_DB_PATH = (DATA_DIR / "astra_me_v3.db").as_posix()
STATIC_DIR = BASE_DIR / "app" / "static"
STATIC_DIR.mkdir(parents=True, exist_ok=True)
REPORTS_DIR = STATIC_DIR / "reports"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


class Settings(BaseSettings):
    PROJECT_NAME: str = "Astra-Me (Fire-fly)"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str = f"sqlite:///{DEFAULT_DB_PATH}"
    SQL_ECHO: bool = False
    KNOW_TIMES_BATCH_SIZE: int = 10

    # LLM Configuration
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = "https://api.openai.com/v1"
    LLM_MODEL: str = "gpt-3.5-turbo"
    LLM_EMBEDDING_MODEL: str = "text-embedding-ada-002"

    # TTS Configuration (SiliconFlow)
    TTS_API_KEY: str = ""
    TTS_BASE_URL: str = "https://api.siliconflow.cn/v1"
    ALLOW_BACKEND_TTS: bool = False

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
