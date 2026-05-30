#!/bin/bash
# =============================================================================
# ФинАссистент — скрипт деплоя preview-версии
# Запускать из корня репозитория: bash deploy.sh
# =============================================================================
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
ENV_FILE="$BACKEND_DIR/.env"

echo "=== ФинАссистент Deploy ==="
echo "Root: $REPO_ROOT"

# Проверка .env
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Файл $ENV_FILE не найден."
    echo "   Скопируйте backend/.env.example → backend/.env и заполните переменные."
    exit 1
fi

# Обновляем код
echo ""
echo "📥 Обновляем код..."
git -C "$REPO_ROOT" pull --ff-only origin main

# Собираем и поднимаем всё
echo ""
echo "🐳 Собираем Docker-образы..."
docker compose -f "$BACKEND_DIR/docker-compose.yml" build --parallel

echo ""
echo "🚀 Запускаем контейнеры..."
docker compose -f "$BACKEND_DIR/docker-compose.yml" up -d

# Ждём БД
echo ""
echo "⏳ Ждём PostgreSQL..."
docker compose -f "$BACKEND_DIR/docker-compose.yml" exec postgres \
    sh -c 'until pg_isready -U $POSTGRES_USER -d $POSTGRES_DB; do sleep 1; done'

echo ""
echo "✅ Деплой завершён!"
echo ""
echo "Доступные адреса:"
echo "  Приложение:       http://localhost"
echo "  Traefik Dashboard: http://localhost:8080"
echo "  Flower (Celery):   http://localhost:5555"
echo ""
echo "Статус контейнеров:"
docker compose -f "$BACKEND_DIR/docker-compose.yml" ps
