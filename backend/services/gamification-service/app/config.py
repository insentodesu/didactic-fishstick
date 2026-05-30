from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str
    jwt_algorithm: str = "HS256"
    gamification_db_url: str
    redis_url: str

    # Параметры механики тамагочи
    tamagochi_hunger_decay_per_hour: int = 5     # сколько очков голода теряется в час
    tamagochi_hunger_per_100rub: int = 10        # сколько голода восстанавливает 100 ₽ накоплений
    tamagochi_exp_per_100rub: int = 5            # сколько опыта даёт 100 ₽
    tamagochi_level_up_exp: int = 100            # опыт до следующего уровня (линейно)


settings = Settings()
