-- ============================================================
-- ClickHouse: аналитические события
-- Используется для построения BI-дашбордов и поведенческой аналитики
-- ============================================================

CREATE DATABASE IF NOT EXISTS analytics;

-- Поток финансовых событий (партиционирование по месяцам)
CREATE TABLE IF NOT EXISTS analytics.financial_events (
    event_id        UUID,
    user_id         UUID,
    event_type      LowCardinality(String),  -- 'transaction_added', 'goal_created', 'subscription_cancelled', etc.
    amount          Nullable(Decimal(15, 2)),
    currency        FixedString(3),
    category        LowCardinality(String),
    merchant        String,
    metadata        String,                  -- JSON-строка
    session_id      Nullable(UUID),
    occurred_at     DateTime64(3, 'Europe/Moscow'),
    date            Date MATERIALIZED toDate(occurred_at)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (user_id, occurred_at)
TTL date + INTERVAL 2 YEAR;

-- Агрегаты расходов по категориям (обновляются ежечасно)
CREATE TABLE IF NOT EXISTS analytics.spending_by_category_hourly (
    user_id         UUID,
    category        LowCardinality(String),
    hour            DateTime,
    total_amount    Decimal(15, 2),
    transaction_count UInt32
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (user_id, category, hour);

-- Сессии пользователей
CREATE TABLE IF NOT EXISTS analytics.user_sessions (
    session_id      UUID,
    user_id         UUID,
    started_at      DateTime64(3, 'Europe/Moscow'),
    ended_at        Nullable(DateTime64(3, 'Europe/Moscow')),
    duration_seconds Nullable(UInt32),
    device_type     LowCardinality(String),  -- 'mobile', 'desktop', 'tablet'
    os              LowCardinality(String),
    screens_visited Array(String),
    date            Date MATERIALIZED toDate(started_at)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (user_id, started_at)
TTL date + INTERVAL 1 YEAR;

-- Метрики здоровья сервисов
CREATE TABLE IF NOT EXISTS analytics.service_metrics (
    service         LowCardinality(String),
    endpoint        String,
    method          FixedString(7),
    status_code     UInt16,
    duration_ms     UInt32,
    timestamp       DateTime64(3, 'Europe/Moscow')
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (service, timestamp)
TTL toDate(timestamp) + INTERVAL 30 DAY;

-- Материализованное представление: расходы по дням (для быстрых дашбордов)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.daily_spending_mv
TO analytics.spending_by_category_hourly
AS SELECT
    user_id,
    category,
    toStartOfHour(occurred_at) AS hour,
    sum(amount) AS total_amount,
    count() AS transaction_count
FROM analytics.financial_events
WHERE event_type = 'transaction_added'
GROUP BY user_id, category, hour;
