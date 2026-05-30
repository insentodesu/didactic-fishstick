"""
Celery-воркер: фоновая обработка выписок и переклассификация.
"""

import asyncio
import os
from pathlib import Path

from celery import Celery

from app.config import settings

app = Celery("transaction_worker", broker=settings.celery_broker_url, backend=settings.celery_result_backend)

app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="Europe/Moscow",
    task_routes={
        "app.worker.process_statement": {"queue": "transactions"},
        "app.worker.recategorize_user": {"queue": "transactions"},
        "app.worker.detect_subscriptions": {"queue": "subscriptions"},
    },
)


@app.task(bind=True, max_retries=3, default_retry_delay=30)
def process_statement(self, statement_id: str, file_path: str, user_id: str):
    """
    Обрабатывает загруженную выписку:
      1. Парсит файл
      2. Классифицирует транзакции
      3. Сохраняет в БД
      4. Запускает детектор подписок
      5. Отправляет уведомление о завершении
    """
    from app.services.parser import parse_statement
    from sqlalchemy import create_engine, text

    try:
        content = Path(file_path).read_bytes()
        filename = Path(file_path).name
        transactions, bank_name = parse_statement(content, filename)

        # Синхронный движок для Celery (не async)
        sync_url = settings.transaction_db_url.replace("postgresql+asyncpg://", "postgresql://")
        engine = create_engine(sync_url)

        with engine.connect() as conn:
            for tx in transactions:
                conn.execute(text("""
                    INSERT INTO transactions.transactions
                        (user_id, statement_id, amount, is_income, merchant_name, description, transaction_date)
                    VALUES
                        (:user_id, :stmt_id, :amount, :is_income, :merchant, :desc, :date)
                """), {
                    "user_id": user_id,
                    "stmt_id": statement_id,
                    "amount": float(tx.amount),
                    "is_income": tx.is_income,
                    "merchant": tx.merchant_name,
                    "desc": tx.description,
                    "date": tx.transaction_date.isoformat(),
                })

            conn.execute(text("""
                UPDATE transactions.bank_statements
                SET status = 'done', bank_name = :bank
                WHERE id = :id
            """), {"bank": bank_name, "id": statement_id})
            conn.commit()

        # Удаляем файл после обработки — privacy first
        Path(file_path).unlink(missing_ok=True)

        # Запускаем детектор подписок асинхронно
        detect_subscriptions.delay(user_id)

    except Exception as exc:
        self.retry(exc=exc)


@app.task
def recategorize_user(user_id: str):
    """Переклассифицирует все транзакции пользователя (после обучения новой модели)."""
    pass  # TODO: batch LLM classify


@app.task
def detect_subscriptions(user_id: str):
    """Анализирует транзакции на предмет регулярных подписок."""
    pass  # Делегируется subscription-service через внутренний HTTP
