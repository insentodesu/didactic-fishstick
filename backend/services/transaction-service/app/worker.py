"""
Celery-воркер: фоновая обработка выписок и переклассификация.
"""

import logging
from datetime import datetime
from pathlib import Path

import httpx
from celery import Celery
from sqlalchemy import create_engine, text

from app.config import settings
from app.services.file_to_text import file_to_text

logger = logging.getLogger(__name__)

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


def _sync_engine():
    sync_url = settings.transaction_db_url.replace("postgresql+asyncpg://", "postgresql://")
    return create_engine(sync_url)


def _parse_llm_datetime(raw: str) -> datetime:
    raw = str(raw).strip()
    for fmt in (
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%d.%m.%Y %H:%M:%S",
        "%d.%m.%Y %H:%M",
        "%d.%m.%Y",
        "%Y-%m-%d",
    ):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00").split("+")[0])
    except ValueError:
        return datetime.now()


def _call_llm_parse(text: str, filename: str) -> list[dict]:
    url = f"{settings.llm_service_url.rstrip('/')}/llm/parse-statement"
    with httpx.Client(timeout=180.0) as client:
        resp = client.post(url, json={"text": text, "filename": filename})
        resp.raise_for_status()
        return resp.json().get("transactions", [])


def _fallback_parse(content: bytes, filename: str) -> list[dict]:
    from app.services.parser import parse_statement

    transactions, _ = parse_statement(content, filename)
    return [
        {
            "merchant_name": tx.merchant_name,
            "description": tx.description,
            "amount": float(tx.amount),
            "is_income": tx.is_income,
            "transaction_date": tx.transaction_date.isoformat() + "T12:00:00",
            "category_id": 11 if tx.is_income else 13,
        }
        for tx in transactions
    ]


@app.task(bind=True, max_retries=3, default_retry_delay=30)
def process_statement(self, statement_id: str, file_path: str, user_id: str):
    """
    Обрабатывает загруженную выписку:
      1. Извлекает текст из PDF/Excel/CSV
      2. Отправляет текст в llm-service → JSON транзакций
      3. Сохраняет в БД с датой и временем
      4. Запускает детектор подписок
    """
    engine = _sync_engine()

    try:
        content = Path(file_path).read_bytes()
        filename = Path(file_path).name
        ext = Path(filename).suffix.lower()

        text_repr = file_to_text(content, filename)
        transactions: list[dict] = []

        try:
            transactions = _call_llm_parse(text_repr, filename)
            logger.info("LLM parsed %d transactions from %s", len(transactions), filename)
        except Exception as llm_err:
            logger.warning("LLM parse failed (%s), falling back to local parser", llm_err)
            transactions = _fallback_parse(content, filename)

        if not transactions:
            with engine.connect() as conn:
                conn.execute(text("""
                    UPDATE transactions.bank_statements
                    SET status = 'error', error_message = :msg
                    WHERE id = :id
                """), {"msg": "Не найдено операций в выписке", "id": statement_id})
                conn.commit()
            Path(file_path).unlink(missing_ok=True)
            return

        with engine.connect() as conn:
            for tx in transactions:
                tx_dt = _parse_llm_datetime(tx.get("transaction_date", ""))
                conn.execute(text("""
                    INSERT INTO transactions.transactions
                        (user_id, statement_id, amount, is_income, merchant_name,
                         description, transaction_date, category_id, category_confidence)
                    VALUES
                        (:user_id, :stmt_id, :amount, :is_income, :merchant,
                         :desc, :date, :cat_id, :conf)
                """), {
                    "user_id": user_id,
                    "stmt_id": statement_id,
                    "amount": float(tx["amount"]),
                    "is_income": bool(tx.get("is_income", False)),
                    "merchant": tx.get("merchant_name"),
                    "desc": tx.get("description"),
                    "date": tx_dt.isoformat(),
                    "cat_id": tx.get("category_id"),
                    "conf": 0.85 if tx.get("category_id") else None,
                })

            total_income = sum(float(t['amount']) for t in transactions if t.get('is_income'))
            total_expense = sum(float(t['amount']) for t in transactions if not t.get('is_income'))

            conn.execute(text("""
                UPDATE transactions.bank_statements
                SET status = 'done', bank_name = :bank,
                    total_income = :income, total_expense = :expense
                WHERE id = :id
            """), {"bank": f"llm_{ext.lstrip('.')}", "id": statement_id, "income": total_income, "expense": total_expense})
            conn.commit()

        Path(file_path).unlink(missing_ok=True)
        detect_subscriptions.delay(user_id)

    except Exception as exc:
        logger.exception("process_statement failed for %s", statement_id)
        try:
            with _sync_engine().connect() as conn:
                conn.execute(text("""
                    UPDATE transactions.bank_statements
                    SET status = 'error', error_message = :msg
                    WHERE id = :id
                """), {"msg": str(exc)[:500], "id": statement_id})
                conn.commit()
        except Exception:
            pass
        self.retry(exc=exc)


@app.task(max_retries=2, default_retry_delay=15)
def recategorize_user(user_id: str):
    """
    Категоризирует транзакции без категории через LLM batch classify.
    Обрабатывает батчами по 50 за раз.
    """
    import httpx
    from sqlalchemy import create_engine, text

    sync_url = settings.transaction_db_url.replace("postgresql+asyncpg://", "postgresql://")
    engine = create_engine(sync_url)

    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT id, merchant_name, description
            FROM transactions.transactions
            WHERE user_id = :uid AND category_id IS NULL AND is_deleted = false
            ORDER BY transaction_date DESC
            LIMIT 50
        """), {"uid": user_id}).fetchall()

    if not rows:
        return

    tx_ids = [str(r.id) for r in rows]
    tx_batch = [
        {"merchant_name": r.merchant_name or "", "description": r.description or ""}
        for r in rows
    ]

    try:
        with httpx.Client(timeout=90.0) as client:
            resp = client.post(
                f"{settings.llm_service_url}/llm/classify/batch",
                json={"transactions": tx_batch},
                timeout=90.0,
            )
            if not resp.is_success:
                return
            results = resp.json().get("results", [])
    except Exception:
        return

    if not results:
        return

    with engine.connect() as conn:
        for i, tx_id in enumerate(tx_ids):
            cat_id = results[i].get("category_id", 13) if i < len(results) else 13
            if not isinstance(cat_id, int) or cat_id < 1 or cat_id > 13:
                cat_id = 13
            conn.execute(text("""
                UPDATE transactions.transactions
                SET category_id = :cat, category_confidence = 0.82
                WHERE id = :id AND user_id = :uid
            """), {"cat": cat_id, "id": tx_id, "uid": user_id})
        conn.commit()


@app.task(max_retries=2, default_retry_delay=10)
def detect_subscriptions(user_id: str):
    """Делегирует детект подписок в subscription-service через HTTP."""
    try:
        url = "http://subscription-service:8004/subscriptions/scan"
        with httpx.Client(timeout=30.0) as client:
            client.post(
                "http://subscription-service:8004/subscriptions/scan",
                headers={"X-Internal-User-Id": user_id},
            )
    except Exception:
        pass
