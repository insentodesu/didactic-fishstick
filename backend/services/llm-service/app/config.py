from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"

    # Внутренние настройки AI-провайдера (не публикуются)
    aiesa_base_url: str = "https://api.transcription.aiesa.ru/api/v2"
    aiesa_public_key: str
    aiesa_secret_key: str
    aiesa_model: str = "aiesa-pro"
    aiesa_timeout: int = 60

    # Публичное название модели для API-ответов
    public_model_name: str = "finassist-1"


settings = Settings()
