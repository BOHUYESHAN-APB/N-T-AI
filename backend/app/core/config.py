from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "Astra-Me (Fire-fly)"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str = "sqlite:///./astra_me_v3.db"

    # LLM Configuration
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = "https://api.openai.com/v1"
    LLM_MODEL: str = "gpt-3.5-turbo"

    # Server / HTTPS
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    USE_HTTPS: bool = False
    SSL_CERT_PATH: str = "./certs/cert.pem"
    SSL_KEY_PATH: str = "./certs/key.pem"

    class Config:
        env_file = ".env"


settings = Settings()
