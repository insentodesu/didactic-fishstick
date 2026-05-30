from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"
    subscription_db_url: str
    redis_url: str
    gmail_client_id: str = ""
    gmail_client_secret: str = ""


settings = Settings()
