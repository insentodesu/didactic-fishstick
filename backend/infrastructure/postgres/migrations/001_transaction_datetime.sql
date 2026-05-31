-- Поддержка времени операций (не только даты)
ALTER TABLE transactions.transactions
    ALTER COLUMN transaction_date TYPE TIMESTAMPTZ
    USING transaction_date::timestamptz;

-- Анонимный пользователь для PWA без регистрации
INSERT INTO auth.users (id, email, name, is_active, is_verified)
VALUES ('00000000-0000-0000-0000-000000000000', 'anonymous@finpet.local', 'Anonymous', true, true)
ON CONFLICT (id) DO NOTHING;
