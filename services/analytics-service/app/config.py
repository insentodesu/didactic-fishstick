from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"

    analytics_db_url: str
    clickhouse_host: str = "clickhouse"
    clickhouse_port: int = 8123
    clickhouse_db: str = "analytics"
    clickhouse_user: str = "default"
    clickhouse_password: str = ""

    chroma_host: str = "chromadb"
    chroma_port: int = 8000

    transaction_service_url: str = "http://transaction-service:8002"
    llm_service_url: str = "http://llm-service:8009"


settings = Settings()
