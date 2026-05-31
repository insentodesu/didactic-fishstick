-- ============================================================
-- Инициализация схем PostgreSQL
-- Каждый сервис использует свою схему внутри одной БД
-- ============================================================

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS transactions;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS subscriptions;
CREATE SCHEMA IF NOT EXISTS investments;
CREATE SCHEMA IF NOT EXISTS gamification;
CREATE SCHEMA IF NOT EXISTS notifications;
CREATE SCHEMA IF NOT EXISTS receipts;

-- Расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- полнотекстовый поиск по мерчантам

-- ============================================================
-- Схема: auth
-- ============================================================

CREATE TABLE IF NOT EXISTS auth.users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       VARCHAR(255) UNIQUE NOT NULL,
    phone       VARCHAR(20),
    name        VARCHAR(255),
    avatar_url  TEXT,
    password_hash TEXT,                         -- NULL если только OAuth
    is_active   BOOLEAN DEFAULT TRUE,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.oauth_accounts (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider    VARCHAR(50) NOT NULL,           -- 'google', 'yandex'
    provider_user_id VARCHAR(255) NOT NULL,
    access_token TEXT,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    scopes      TEXT[],
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (provider, provider_user_id)
);

CREATE TABLE IF NOT EXISTS auth.refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(64) UNIQUE NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    user_agent  TEXT,
    ip_address  INET
);

CREATE TABLE IF NOT EXISTS auth.password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(64) UNIQUE NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Схема: transactions
-- ============================================================

CREATE TABLE IF NOT EXISTS transactions.bank_statements (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL,
    filename    VARCHAR(500) NOT NULL,
    file_format VARCHAR(20) NOT NULL,           -- 'csv', 'xls', 'xlsx', 'pdf'
    bank_name   VARCHAR(100),
    period_from DATE,
    period_to   DATE,
    total_income    NUMERIC(15, 2) DEFAULT 0,
    total_expense   NUMERIC(15, 2) DEFAULT 0,
    status      VARCHAR(20) DEFAULT 'processing', -- 'processing', 'done', 'error'
    error_message TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions.categories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    name_ru     VARCHAR(100) NOT NULL,
    icon        VARCHAR(50),
    color       VARCHAR(7),                     -- HEX
    parent_id   INTEGER REFERENCES transactions.categories(id),
    is_system   BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS transactions.transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    statement_id    UUID REFERENCES transactions.bank_statements(id) ON DELETE SET NULL,
    external_id     VARCHAR(255),               -- ID транзакции в банке
    amount          NUMERIC(15, 2) NOT NULL,
    currency        CHAR(3) DEFAULT 'RUB',
    is_income       BOOLEAN NOT NULL,
    merchant_name   VARCHAR(500),
    merchant_mcc    VARCHAR(10),
    category_id     INTEGER REFERENCES transactions.categories(id),
    category_confidence FLOAT,                  -- уверенность модели при классификации
    description     TEXT,
    transaction_date TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    is_deleted      BOOLEAN DEFAULT FALSE,
    source          VARCHAR(20)  NOT NULL DEFAULT 'bank_statement'
);

-- Migration for existing deployments
ALTER TABLE transactions.transactions ADD COLUMN IF NOT EXISTS source VARCHAR(20) NOT NULL DEFAULT 'bank_statement';

CREATE TABLE IF NOT EXISTS transactions.merchant_aliases (
    id          SERIAL PRIMARY KEY,
    pattern     VARCHAR(500) NOT NULL,          -- regexp паттерн из выписки
    canonical   VARCHAR(255) NOT NULL,          -- нормализованное имя
    category_id INTEGER REFERENCES transactions.categories(id),
    is_subscription BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_date
    ON transactions.transactions(user_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category
    ON transactions.transactions(user_id, category_id);
CREATE INDEX IF NOT EXISTS idx_merchant_trgm
    ON transactions.transactions USING gin(merchant_name gin_trgm_ops);

-- ============================================================
-- Схема: subscriptions
-- ============================================================

CREATE TABLE IF NOT EXISTS subscriptions.subscriptions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    name            VARCHAR(255) NOT NULL,
    amount          NUMERIC(10, 2) NOT NULL,
    currency        CHAR(3) DEFAULT 'RUB',
    billing_period  VARCHAR(20) NOT NULL,       -- 'monthly', 'yearly', 'weekly'
    next_billing_date DATE,
    last_billing_date DATE,
    merchant_pattern VARCHAR(500),              -- паттерн из выписки
    source          VARCHAR(20) DEFAULT 'auto', -- 'auto', 'gmail', 'manual'
    status          VARCHAR(20) DEFAULT 'active', -- 'active', 'cancelled', 'suspicious'
    category        VARCHAR(100),
    logo_url        TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS subscriptions.subscription_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id UUID NOT NULL REFERENCES subscriptions.subscriptions(id) ON DELETE CASCADE,
    event_type      VARCHAR(50) NOT NULL,       -- 'detected', 'charged', 'cancelled', 'price_changed'
    amount          NUMERIC(10, 2),
    event_date      TIMESTAMPTZ DEFAULT NOW(),
    metadata        JSONB
);

-- ============================================================
-- Схема: investments
-- ============================================================

CREATE TABLE IF NOT EXISTS investments.deposit_offers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bank_name       VARCHAR(255) NOT NULL,
    bank_logo_url   TEXT,
    product_name    VARCHAR(500) NOT NULL,
    rate_percent    NUMERIC(5, 2) NOT NULL,
    rate_type       VARCHAR(20) DEFAULT 'fixed', -- 'fixed', 'floating'
    min_amount      NUMERIC(15, 2),
    max_amount      NUMERIC(15, 2),
    term_days_min   INTEGER,
    term_days_max   INTEGER,
    capitalization  BOOLEAN DEFAULT FALSE,
    early_withdrawal BOOLEAN DEFAULT FALSE,
    online_only     BOOLEAN DEFAULT FALSE,
    offer_url       TEXT,
    is_active       BOOLEAN DEFAULT TRUE,
    fetched_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS investments.savings_goals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    title           VARCHAR(255) NOT NULL,
    target_amount   NUMERIC(15, 2) NOT NULL,
    current_amount  NUMERIC(15, 2) DEFAULT 0,
    target_date     DATE,
    monthly_required NUMERIC(10, 2),
    linked_deposit_id UUID REFERENCES investments.deposit_offers(id),
    status          VARCHAR(20) DEFAULT 'active', -- 'active', 'achieved', 'paused'
    emoji           VARCHAR(10),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS investments.goal_contributions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    goal_id         UUID NOT NULL REFERENCES investments.savings_goals(id) ON DELETE CASCADE,
    amount          NUMERIC(10, 2) NOT NULL,
    note            TEXT,
    contributed_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Схема: gamification
-- ============================================================

CREATE TABLE IF NOT EXISTS gamification.tamagochi (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL,
    name            VARCHAR(100) DEFAULT 'Монетка',
    species         VARCHAR(50) DEFAULT 'cat',
    level           INTEGER DEFAULT 1,
    experience      INTEGER DEFAULT 0,
    hunger          INTEGER DEFAULT 100,        -- 0-100, убывает со временем
    happiness       INTEGER DEFAULT 100,        -- 0-100
    health          INTEGER DEFAULT 100,        -- 0-100
    is_alive        BOOLEAN DEFAULT TRUE,
    total_fed_amount NUMERIC(15, 2) DEFAULT 0,  -- сколько всего «накормлено»
    last_fed_at     TIMESTAMPTZ,
    last_hunger_decay_at TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gamification.feeding_history (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    amount          NUMERIC(10, 2) NOT NULL,    -- сумма сэкономленного
    hunger_restored INTEGER NOT NULL,
    exp_gained      INTEGER NOT NULL,
    fed_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gamification.streaks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL,
    current_streak  INTEGER DEFAULT 0,
    longest_streak  INTEGER DEFAULT 0,
    last_check_in   DATE,
    total_check_ins INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gamification.achievements (
    id              SERIAL PRIMARY KEY,
    code            VARCHAR(100) UNIQUE NOT NULL,
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    icon            VARCHAR(50),
    points          INTEGER DEFAULT 0,
    condition_type  VARCHAR(50),                -- 'streak', 'savings', 'transactions', 'level'
    condition_value INTEGER
);

CREATE TABLE IF NOT EXISTS gamification.user_achievements (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    achievement_id  INTEGER NOT NULL REFERENCES gamification.achievements(id),
    earned_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, achievement_id)
);

CREATE TABLE IF NOT EXISTS gamification.daily_challenges (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    challenge_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    reward_points   INTEGER DEFAULT 10,
    reward_hunger   INTEGER DEFAULT 20,
    is_completed    BOOLEAN DEFAULT FALSE,
    completed_at    TIMESTAMPTZ,
    UNIQUE (user_id, challenge_date, title)
);

CREATE TABLE IF NOT EXISTS gamification.leagues (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    season          INTEGER NOT NULL,           -- номер недели/месяца
    points          INTEGER DEFAULT 0,
    rank            INTEGER,
    league_tier     VARCHAR(20) DEFAULT 'bronze', -- 'bronze', 'silver', 'gold', 'diamond'
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, season)
);

-- ============================================================
-- Схема: notifications
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications.notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    type            VARCHAR(50) NOT NULL,       -- 'subscription', 'goal', 'tamagochi', 'system', 'anomaly'
    title           VARCHAR(500) NOT NULL,
    body            TEXT,
    action_url      TEXT,
    metadata        JSONB,
    is_read         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications.preferences (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL,
    subscription_alerts  BOOLEAN DEFAULT TRUE,
    goal_progress        BOOLEAN DEFAULT TRUE,
    tamagochi_hunger     BOOLEAN DEFAULT TRUE,
    anomaly_alerts       BOOLEAN DEFAULT TRUE,
    weekly_digest        BOOLEAN DEFAULT TRUE,
    push_enabled         BOOLEAN DEFAULT FALSE,
    quiet_hours_from     TIME,
    quiet_hours_to       TIME,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Схема: receipts
-- ============================================================

CREATE TABLE IF NOT EXISTS receipts.receipts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,
    qr_raw          TEXT,                       -- сырой контент QR
    fn              VARCHAR(20),                -- фискальный номер
    fd              VARCHAR(20),                -- номер фискального документа
    fp              VARCHAR(20),                -- фискальный признак
    purchase_date   TIMESTAMPTZ,
    total_amount    NUMERIC(10, 2),
    seller_name     VARCHAR(500),
    seller_inn      VARCHAR(12),
    seller_address  TEXT,
    items           JSONB,                      -- массив позиций [{name, price, qty}]
    raw_fns_response JSONB,
    status          VARCHAR(20) DEFAULT 'pending', -- 'pending', 'processed', 'error'
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications.notifications(user_id, is_read, created_at DESC);

-- Анонимный пользователь (PWA без регистрации)
INSERT INTO auth.users (id, email, name, is_active, is_verified)
VALUES ('00000000-0000-0000-0000-000000000000', 'anonymous@finpet.local', 'Anonymous', true, true)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Базовые категории транзакций
-- ============================================================

INSERT INTO transactions.categories (name, name_ru, icon, color) VALUES
    ('food',            'Еда и рестораны',     '🍕', '#FF6B6B'),
    ('transport',       'Транспорт',            '🚗', '#4ECDC4'),
    ('shopping',        'Покупки',              '🛍️', '#45B7D1'),
    ('entertainment',   'Развлечения',          '🎬', '#96CEB4'),
    ('health',          'Здоровье',             '💊', '#FFEAA7'),
    ('utilities',       'ЖКУ и связь',          '🏠', '#DDA0DD'),
    ('subscriptions',   'Подписки',             '📱', '#98D8C8'),
    ('education',       'Образование',          '📚', '#F7DC6F'),
    ('travel',          'Путешествия',          '✈️', '#82E0AA'),
    ('finance',         'Финансы и кредиты',    '💳', '#F8C471'),
    ('income',          'Доходы',               '💰', '#2ECC71'),
    ('transfer',        'Переводы',             '🔄', '#AEB6BF'),
    ('other',           'Прочее',               '📦', '#BDC3C7')
ON CONFLICT DO NOTHING;

-- ============================================================
-- Достижения
-- ============================================================

INSERT INTO gamification.achievements (code, title, description, icon, points, condition_type, condition_value) VALUES
    ('first_upload',        'Первый шаг',           'Загрузили первую выписку',             '📄', 50,  'transactions', 1),
    ('streak_7',            'Неделя подряд',         '7 дней активности подряд',             '🔥', 100, 'streak',       7),
    ('streak_30',           'Месяц без пропусков',   '30 дней активности подряд',            '💪', 500, 'streak',       30),
    ('saver_1000',          'Первая тысяча',         'Сэкономили 1 000 рублей',              '🪙', 50,  'savings',      1000),
    ('saver_10000',         'Серьёзная копилка',     'Сэкономили 10 000 рублей',             '💎', 200, 'savings',      10000),
    ('goal_achieved',       'Цель достигнута!',      'Достигли первой финансовой цели',      '🎯', 300, 'goal',         1),
    ('subscription_hunter', 'Охотник за подписками', 'Нашли и отменили 3 лишних подписки',  '🔍', 150, 'cancelled',    3),
    ('tamagochi_lvl5',      'Питомец растёт',        'Питомец достиг 5 уровня',              '🐾', 200, 'level',        5),
    ('transactions_100',    'Аналитик',             'Проанализировали 100 транзакций',       '📊', 100, 'transactions', 100)
ON CONFLICT DO NOTHING;
