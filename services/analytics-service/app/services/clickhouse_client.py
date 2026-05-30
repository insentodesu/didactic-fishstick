import clickhouse_connect

from app.config import settings

_client = None


def get_clickhouse_client():
    global _client
    if _client is None:
        _client = clickhouse_connect.get_client(
            host=settings.clickhouse_host,
            port=settings.clickhouse_port,
            database=settings.clickhouse_db,
            username=settings.clickhouse_user,
            password=settings.clickhouse_password,
        )
    return _client


def track_event(user_id: str, event_type: str, amount: float | None = None,
                category: str = "", merchant: str = "", metadata: str = "{}"):
    """Записывает финансовое событие в ClickHouse для аналитики."""
    client = get_clickhouse_client()
    client.insert("financial_events", [
        [None, user_id, event_type, amount, "RUB", category, merchant, metadata, None, None]
    ], column_names=["event_id", "user_id", "event_type", "amount", "currency",
                     "category", "merchant", "metadata", "session_id", "occurred_at"])
