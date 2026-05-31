import logging
import os
import uuid
from datetime import date, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status

logger = logging.getLogger(__name__)
from sqlalchemy import func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.schemas.transaction import (
    CategoryStatsResponse,
    ManualTransactionRequest,
    MerchantStatsResponse,
    TransactionListResponse,
    TransactionResponse,
    TransactionSummaryResponse,
    UpdateCategoryRequest,
    UploadStatementResponse,
)
from app.services.deps import get_current_user_id
from app.worker import process_statement

router = APIRouter(prefix="/transactions", tags=["Транзакции"])

ALLOWED_EXTENSIONS = {".csv", ".xls", ".xlsx", ".pdf"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff", ".heic"}


def _row_to_response(row) -> TransactionResponse:
    data = dict(row._mapping if hasattr(row, "_mapping") else row)
    data["category"] = data.pop("category_name", None)
    data.setdefault("category_icon", None)
    data.setdefault("source", "bank_statement")
    return TransactionResponse.model_validate(data)


@router.post("/upload", response_model=UploadStatementResponse, status_code=status.HTTP_202_ACCEPTED)
async def upload_statement(
    file: Annotated[UploadFile, File(description="Выписка: CSV/XLS/XLSX/PDF")],
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    demo: bool = Query(False, description="Демо-режим: mock-выписка с симуляцией LLM"),
):
    """Загружает выписку из банка и ставит задачу обработки в очередь."""
    ext = os.path.splitext(file.filename or "")[1].lower()
    content = await file.read()

    if demo and not content:
        demo_path = os.path.join(os.path.dirname(__file__), "..", "data", "demo_statement.csv")
        with open(demo_path, "rb") as demo_file:
            content = demo_file.read()
        ext = ext or ".csv"

    if ext in IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail="Загрузка изображений не поддерживается. Используйте PDF, Excel или CSV.",
        )
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Поддерживаются только CSV, XLS, XLSX, PDF")

    if len(content) > settings.max_upload_size_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"Файл слишком большой (макс {settings.max_upload_size_mb} МБ)")

    statement_id = str(uuid.uuid4())
    display_name = file.filename or ("demo-alfa-statement.csv" if demo else f"statement{ext}")
    file_path = os.path.join(settings.upload_dir, f"{statement_id}{ext or '.csv'}")
    os.makedirs(settings.upload_dir, exist_ok=True)

    with open(file_path, "wb") as f:
        f.write(content)

    await db.execute(text("""
        INSERT INTO transactions.bank_statements (id, user_id, filename, file_format, status)
        VALUES (:id, :user_id, :filename, :fmt, 'processing')
    """), {
        "id": statement_id,
        "user_id": user_id,
        "filename": display_name,
        "fmt": ext.lstrip(".") or "csv",
    })
    await db.commit()

    logger.info(
        "Statement upload accepted statement_id=%s user_id=%s filename=%s bytes=%d is_demo=%s",
        statement_id, user_id, display_name, len(content), demo,
    )

    try:
        process_statement.delay(statement_id, file_path, user_id, demo)
    except Exception:
        logger.warning("Failed to queue process_statement task for statement %s", statement_id)

    return UploadStatementResponse(statement_id=statement_id, status="processing")


@router.get("/", response_model=TransactionListResponse)
async def list_transactions(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    date_from: date | None = None,
    date_to: date | None = None,
    category_id: int | None = None,
    is_income: bool | None = None,
    search: str | None = None,
):
    """Список транзакций с фильтрами и пагинацией."""
    logger.info(
        "Listing transactions user_id=%s page=%d page_size=%d is_income=%s search=%s",
        user_id, page, page_size, is_income, search,
    )
    filters = ["user_id = :user_id", "is_deleted = false"]
    params: dict = {"user_id": user_id}

    if date_from:
        filters.append("transaction_date >= :date_from")
        params["date_from"] = date_from
    if date_to:
        filters.append("transaction_date <= :date_to")
        params["date_to"] = date_to
    if category_id is not None:
        filters.append("category_id = :category_id")
        params["category_id"] = category_id
    if is_income is not None:
        filters.append("is_income = :is_income")
        params["is_income"] = is_income
    if search:
        filters.append("merchant_name ILIKE :search")
        params["search"] = f"%{search}%"

    where = " AND ".join(filters)
    count_result = await db.execute(text(f"SELECT COUNT(*) FROM transactions.transactions WHERE {where}"), params)
    total = count_result.scalar()

    offset = (page - 1) * page_size
    params["limit"] = page_size
    params["offset"] = offset
    rows = await db.execute(text(f"""
        SELECT t.id, t.amount, t.is_income, t.merchant_name, t.category_id, t.category_confidence,
               t.description, t.transaction_date, t.created_at, t.source,
               c.name_ru AS category_name, c.icon AS category_icon
        FROM transactions.transactions t
        LEFT JOIN transactions.categories c ON c.id = t.category_id
        WHERE {where}
        ORDER BY t.transaction_date DESC, t.created_at DESC
        LIMIT :limit OFFSET :offset
    """), params)

    items = [_row_to_response(r) for r in rows]
    return TransactionListResponse(items=items, total=total, page=page, page_size=page_size)


@router.get("/stats", response_model=TransactionSummaryResponse)
async def get_stats(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    date_from: date | None = None,
    date_to: date | None = None,
):
    """Сводная статистика: доходы, расходы, баланс за период."""
    params: dict = {"user_id": user_id}
    date_filter = ""
    if date_from:
        date_filter += " AND transaction_date >= :date_from"
        params["date_from"] = date_from
    if date_to:
        date_filter += " AND transaction_date <= :date_to"
        params["date_to"] = date_to

    result = await db.execute(text(f"""
        SELECT
            COALESCE(SUM(amount) FILTER (WHERE is_income), 0)     AS total_income,
            COALESCE(SUM(amount) FILTER (WHERE NOT is_income), 0) AS total_expense,
            COUNT(*)                                               AS total_count
        FROM transactions.transactions
        WHERE user_id = :user_id AND is_deleted = false {date_filter}
    """), params)
    row = result.mappings().one()
    return TransactionSummaryResponse(
        total_income=row["total_income"],
        total_expense=row["total_expense"],
        balance=row["total_income"] - row["total_expense"],
        total_count=row["total_count"],
    )


@router.get("/categories", response_model=list[CategoryStatsResponse])
async def spending_by_category(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    date_from: date | None = None,
    date_to: date | None = None,
):
    """Расходы по категориям за период (для пирога/бара)."""
    params: dict = {"user_id": user_id}
    date_filter = ""
    if date_from:
        date_filter += " AND t.transaction_date >= :date_from"
        params["date_from"] = date_from
    if date_to:
        date_filter += " AND t.transaction_date <= :date_to"
        params["date_to"] = date_to

    rows = await db.execute(text(f"""
        SELECT c.name_ru, c.icon, c.color, SUM(t.amount) AS total, COUNT(*) AS cnt
        FROM transactions.transactions t
        LEFT JOIN transactions.categories c ON c.id = t.category_id
        WHERE t.user_id = :user_id AND t.is_income = false AND t.is_deleted = false {date_filter}
        GROUP BY c.name_ru, c.icon, c.color
        ORDER BY total DESC
    """), params)
    return [CategoryStatsResponse.model_validate(dict(r._mapping)) for r in rows]


@router.get("/merchants", response_model=list[MerchantStatsResponse])
async def top_merchants(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(10, ge=1, le=50),
):
    """Топ мерчантов по сумме расходов за последние 30 дней."""
    rows = await db.execute(text("""
        SELECT merchant_name, SUM(amount) AS total, COUNT(*) AS cnt
        FROM transactions.transactions
        WHERE user_id = :user_id AND is_income = false AND is_deleted = false
          AND transaction_date >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY merchant_name
        ORDER BY total DESC
        LIMIT :limit
    """), {"user_id": user_id, "limit": limit})
    return [MerchantStatsResponse.model_validate(dict(r._mapping)) for r in rows]


@router.get("/timeline")
async def monthly_timeline(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    months: int = Query(6, ge=1, le=24),
):
    """Помесячная разбивка доходов и расходов."""
    rows = await db.execute(text("""
        SELECT
            DATE_TRUNC('month', transaction_date) AS month,
            SUM(amount) FILTER (WHERE is_income)     AS income,
            SUM(amount) FILTER (WHERE NOT is_income) AS expense
        FROM transactions.transactions
        WHERE user_id = :user_id AND is_deleted = false
          AND transaction_date >= CURRENT_DATE - (:months || ' months')::INTERVAL
        GROUP BY 1
        ORDER BY 1
    """), {"user_id": user_id, "months": months})
    return [dict(r._mapping) for r in rows]


@router.post("/manual", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
async def create_manual_transaction(
    body: ManualTransactionRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Ручное добавление транзакции пользователем (без выписки)."""
    tx_id = str(uuid.uuid4())
    tx_date = body.transaction_date or datetime.utcnow()

    # Resolve category_id by Russian name or use sensible defaults
    category_id = 11 if body.is_income else 13  # 11=Доходы, 13=Прочее
    if body.category_name:
        row = (await db.execute(
            text("SELECT id FROM transactions.categories WHERE name_ru = :name LIMIT 1"),
            {"name": body.category_name},
        )).one_or_none()
        if row:
            category_id = row[0]

    await db.execute(text("""
        INSERT INTO transactions.transactions
            (id, user_id, amount, is_income, merchant_name, description,
             category_id, category_confidence, transaction_date, source)
        VALUES
            (:id, :user_id, :amount, :is_income, :merchant, :desc,
             :cat_id, 1.0, :date, 'manual')
    """), {
        "id": tx_id, "user_id": user_id,
        "amount": abs(body.amount), "is_income": body.is_income,
        "merchant": body.description, "desc": body.description,
        "cat_id": category_id, "date": tx_date,
    })
    await db.commit()
    return await get_transaction(tx_id, db, user_id)


@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction(
    transaction_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(text("""
        SELECT t.id, t.amount, t.is_income, t.merchant_name, t.category_id, t.category_confidence,
               t.description, t.transaction_date, t.created_at, t.source,
               c.name_ru AS category_name, c.icon AS category_icon
        FROM transactions.transactions t
        LEFT JOIN transactions.categories c ON c.id = t.category_id
        WHERE t.id = :id AND t.user_id = :user_id AND t.is_deleted = false
    """), {"id": transaction_id, "user_id": user_id})
    row = result.mappings().one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Транзакция не найдена")
    return _row_to_response(row)


@router.put("/{transaction_id}/category", response_model=TransactionResponse)
async def update_category(
    transaction_id: str,
    body: UpdateCategoryRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Ручная коррекция категории транзакции пользователем."""
    await db.execute(text("""
        UPDATE transactions.transactions
        SET category_id = :cat, category_confidence = 1.0
        WHERE id = :id AND user_id = :user_id AND is_deleted = false
    """), {"cat": body.category_id, "id": transaction_id, "user_id": user_id})
    await db.commit()
    return await get_transaction(transaction_id, db, user_id)


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE transactions.transactions SET is_deleted = true
        WHERE id = :id AND user_id = :user_id
    """), {"id": transaction_id, "user_id": user_id})
    await db.commit()


@router.post("/categorize", status_code=status.HTTP_202_ACCEPTED)
async def batch_recategorize(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Запускает переклассификацию всех транзакций пользователя через LLM."""
    from app.worker import recategorize_user
    recategorize_user.delay(user_id)
    return {"status": "queued"}


@router.get("/export")
async def export_transactions(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    date_from: date | None = None,
    date_to: date | None = None,
):
    """Экспорт транзакций в CSV."""
    from fastapi.responses import StreamingResponse
    import csv
    import io

    params: dict = {"user_id": user_id}
    date_filter = ""
    if date_from:
        date_filter += " AND transaction_date >= :date_from"
        params["date_from"] = date_from
    if date_to:
        date_filter += " AND transaction_date <= :date_to"
        params["date_to"] = date_to

    rows = await db.execute(text(f"""
        SELECT transaction_date, merchant_name, amount, is_income, description
        FROM transactions.transactions
        WHERE user_id = :user_id AND is_deleted = false {date_filter}
        ORDER BY transaction_date DESC
    """), params)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Дата", "Мерчант", "Сумма", "Тип", "Описание"])
    for row in rows:
        writer.writerow([
            row.transaction_date,
            row.merchant_name,
            float(row.amount),
            "Доход" if row.is_income else "Расход",
            row.description,
        ])

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=transactions.csv"},
    )
