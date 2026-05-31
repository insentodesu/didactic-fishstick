from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"
    receipt_db_url: str
    transaction_db_url: str = ""
    fns_api_url: str = "https://proverkacheka.com/api/v1"
    fns_client_secret: str = ""
    upload_dir: str = "/tmp/uploads"
    nalog_lkdr_token: str = ""
    nalog_lkdr_refresh_token: str = ""

    @property
    def tx_db_url(self) -> str:
        return self.transaction_db_url or self.receipt_db_url


settings = Settings()
