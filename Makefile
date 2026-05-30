.PHONY: up down build logs ps clean dev

# Запуск всего стека
up:
	docker compose up -d

# Запуск только инфраструктуры (БД, Redis, Chroma, Ollama)
infra:
	docker compose up -d postgres clickhouse redis chromadb ollama

# Сборка образов
build:
	docker compose build

# Остановка
down:
	docker compose down

# Логи конкретного сервиса: make logs s=auth-service
logs:
	docker compose logs -f $(s)

# Статус контейнеров
ps:
	docker compose ps

# Полная очистка (включая тома)
clean:
	docker compose down -v --remove-orphans

# Миграции БД (применяет init.sql)
migrate:
	docker compose exec postgres psql -U finassist -d finassist -f /docker-entrypoint-initdb.d/init.sql

# Подтянуть LLM модель вручную
pull-model:
	docker compose exec ollama ollama pull llama3.1:8b

# Открыть psql
psql:
	docker compose exec postgres psql -U finassist -d finassist

# Открыть redis-cli
redis-cli:
	docker compose exec redis redis-cli
