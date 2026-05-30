from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"

    ollama_base_url: str = "http://ollama:11434"
    ollama_model: str = "llama3.1:8b"
    ollama_timeout: int = 120

    chroma_host: str = "chromadb"
    chroma_port: int = 8000
    chroma_collection_finance: str = "finance_docs"


settings = Settings()
