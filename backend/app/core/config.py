from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Astra-Me (Fire-fly)"
    API_V1_STR: str = "/api/v1"
    DATABASE_URL: str = "sqlite:///./astra_me_v3.db"
    
    # LLM Configuration
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = "https://api.openai.com/v1"
    LLM_MODEL: str = "gpt-3.5-turbo"

    class Config:
        env_file = ".env"

settings = Settings()
