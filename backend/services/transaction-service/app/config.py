from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"

    transaction_db_url: str
    redis_url: str
    celery_broker_url: str
    celery_result_backend: str

    upload_dir: str = "/tmp/uploads"
    max_upload_size_mb: int = 50

    llm_service_url: str = "http://llm-service:8009"


settings = Settings()
