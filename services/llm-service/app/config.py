from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"

    aiesa_base_url: str = "https://api.transcription.aiesa.ru/api/v2"
    aiesa_public_key: str
    aiesa_secret_key: str
    aiesa_model: str = "aiesa-pro"
    aiesa_timeout: int = 60


settings = Settings()
