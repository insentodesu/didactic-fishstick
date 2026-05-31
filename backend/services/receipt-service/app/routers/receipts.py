import json
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.deps import get_current_user_id
from app.services.fns_client import get_receipt_data

router = APIRouter(prefix="/receipts", tags=["Чеки"])

# Категория «Еда и рестораны» для чеков
RECEIPT_CATEGORY_ID = 1


async def _insert_receipt_transaction(
    db: AsyncSession,
    user_id: str,
    receipt_id: str,
    parsed: dict,
    details: dict | None,
) -> None:
    """Создаёт запись в transactions.transactions для отображения в истории операций."""
    fn, fd, fp = parsed.get("fn"), parsed.get("fd"), parsed.get("fp")
    external_id = f"receipt:{fn}:{fd}:{fp}" if fn and fd and fp else f"receipt:{receipt_id}"

    existing = await db.execute(text("""
        SELECT id FROM transactions.transactions
        WHERE user_id = :uid AND external_id = :ext AND is_deleted = false
        LIMIT 1
    """), {"uid": user_id, "ext": external_id})
    if existing.scalar():
        return

    amount = None
    merchant = None
    purchase_date = None
    description = "Покупка по чеку"

    if details:
        amount = details.get("total_amount")
        merchant = details.get("seller_name")
        purchase_date = details.get("purchase_date")
        items_count = details.get("items_count", 0)
        if items_count:
            description = f"Чек: {items_count} поз."

    if amount is None:
        amount = parsed.get("amount")
    if merchant is None:
        merchant = "Магазин"
    if purchase_date is None:
        purchase_date = parsed.get("purchase_date")

    if not amount or float(amount) <= 0:
        return

    tx_datetime = datetime.now()
    if purchase_date:
        if isinstance(purchase_date, datetime):
            tx_datetime = purchase_date
        else:
            try:
                tx_datetime = datetime.fromisoformat(str(purchase_date).replace("Z", "+00:00"))
            except ValueError:
                pass

    await db.execute(text("""
        INSERT INTO transactions.transactions
            (user_id, external_id, amount, is_income, merchant_name, description,
             transaction_date, category_id, category_confidence)
        VALUES
            (:uid, :ext, :amount, false, :merchant, :desc, :date, :cat, 0.9)
    """), {
        "uid": user_id,
        "ext": external_id,
        "amount": float(amount),
        "merchant": str(merchant)[:500],
        "desc": description,
        "date": tx_datetime,
        "cat": RECEIPT_CATEGORY_ID,
    })


class QRScanRequest(BaseModel):
    qr_raw: str


@router.post("/qr", status_code=status.HTTP_201_CREATED)
async def scan_qr(
    body: QRScanRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """
    Расшифровывает QR-код кассового чека.

    Алгоритм:
      1. Парсим параметры из QR-строки (fn, fd, fp, сумма, дата)
      2. Валидируем формат параметров локально
      3. Запрашиваем полную детализацию через proverkacheka.com API
      4. Сохраняем результат в БД

    Без API ключа (FNS_CLIENT_SECRET) возвращает данные из QR без списка позиций.
    Ключ: зарегистрироваться на proverkacheka.com → Личный кабинет → API.
    """
    result = await get_receipt_data(body.qr_raw)

    if not result["valid"]:
        raise HTTPException(status_code=400, detail=result["error"])

    parsed = result["parsed"]
    details = result["details"]

    receipt_id = str(uuid.uuid4())
    await db.execute(text("""
        INSERT INTO receipts.receipts
            (id, user_id, qr_raw, fn, fd, fp, total_amount, seller_name, seller_inn,
             seller_address, items, raw_fns_response, status)
        VALUES (:id, :uid, :qr, :fn, :fd, :fp, :amount, :seller, :inn, :addr, :items, :raw, :status)
    """), {
        "id": receipt_id,
        "uid": user_id,
        "qr": body.qr_raw,
        "fn": parsed.get("fn"),
        "fd": parsed.get("fd"),
        "fp": parsed.get("fp"),
        "amount": details["total_amount"] if details else parsed.get("amount"),
        "seller": details["seller_name"] if details else None,
        "inn": details["seller_inn"] if details else None,
        "addr": details["seller_address"] if details else None,
        "items": json.dumps(details["items"], ensure_ascii=False) if details else None,
        "raw": json.dumps(details, ensure_ascii=False) if details else None,
        "status": "processed" if details else "partial",
    })

    await _insert_receipt_transaction(db, user_id, receipt_id, {
        "fn": parsed.get("fn"),
        "fd": parsed.get("fd"),
        "fp": parsed.get("fp"),
        "amount": details["total_amount"] if details else parsed.get("amount"),
        "purchase_date": (
            details.get("purchase_date") if details
            else parsed.get("purchase_date") or parsed.get("purchase_date_iso")
        ),
    }, details)
    await db.commit()

    # Создаём транзакцию из чека
    total = details["total_amount"] if details else float(parsed.get("amount") or 0)
    seller = details["seller_name"] if details else "Магазин"
    if total > 0:
        tx_id = str(uuid.uuid4())
        # Определяем категорию: еда = 1, прочее = 13
        items = details.get("items", []) if details else []
        category_id = 1 if any(
            w in " ".join(i.get("name", "").lower() for i in items)
            for w in ("молоко", "хлеб", "сыр", "кефир", "мясо", "рыба", "овощ", "фрукт", "колбас", "творог")
        ) else 13
        await db.execute(text("""
            INSERT INTO transactions.transactions
                (id, user_id, amount, is_income, merchant_name, description, transaction_date, category_id, category_confidence)
            VALUES (:id, :uid, :amount, false, :merchant, :desc, CURRENT_DATE, :cat, 0.7)
            ON CONFLICT DO NOTHING
        """), {
            "id": tx_id,
            "uid": user_id,
            "amount": total,
            "merchant": (seller or "Магазин")[:500],
            "desc": f"Чек #{receipt_id[:8]}",
            "cat": category_id,
        })
        await db.commit()

    return {
        "receipt_id": receipt_id,
        "valid": result["valid"],
        "has_details": result["has_details"],
        "parsed": parsed,
        "details": details,
        "warning": result["error"] if not result["has_details"] else None,
    }


@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_receipt_image(
    file: Annotated[UploadFile, File(description="Фото чека (JPG/PNG)")],
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """
    Загружает фото чека. В будущем: OCR + детектор QR через pyzbar/zxing.
    Сейчас: сохраняет файл и ставит статус pending.
    """
    import os
    from app.config import settings

    content = await file.read()
    if len(content) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Файл слишком большой (макс 10 МБ)")

    os.makedirs(settings.upload_dir, exist_ok=True)
    receipt_id = str(uuid.uuid4())
    ext = os.path.splitext(file.filename or ".jpg")[1]
    file_path = os.path.join(settings.upload_dir, f"receipt_{receipt_id}{ext}")

    with open(file_path, "wb") as f:
        f.write(content)

    await db.execute(text("""
        INSERT INTO receipts.receipts (id, user_id, status)
        VALUES (:id, :uid, 'pending')
    """), {"id": receipt_id, "uid": user_id})
    await db.commit()

    return {"receipt_id": receipt_id, "status": "pending", "message": "OCR в обработке"}


@router.get("/")
async def list_receipts(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    rows = await db.execute(text("""
        SELECT id, seller_name, total_amount, purchase_date, status, created_at
        FROM receipts.receipts
        WHERE user_id = :uid
        ORDER BY created_at DESC
        LIMIT 100
    """), {"uid": user_id})
    return [dict(r._mapping) for r in rows]


@router.get("/stats")
async def receipt_stats(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE status = 'processed') AS processed,
            COALESCE(SUM(total_amount) FILTER (WHERE status = 'processed'), 0) AS total_amount
        FROM receipts.receipts WHERE user_id = :uid
    """), {"uid": user_id})
    return dict(row.mappings().one())


@router.get("/{receipt_id}")
async def get_receipt(
    receipt_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM receipts.receipts WHERE id = :id AND user_id = :uid
    """), {"id": receipt_id, "uid": user_id})
    r = row.mappings().one_or_none()
    if not r:
        raise HTTPException(status_code=404, detail="Чек не найден")
    return dict(r)


@router.delete("/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_receipt(
    receipt_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("DELETE FROM receipts.receipts WHERE id = :id AND user_id = :uid"),
                     {"id": receipt_id, "uid": user_id})
    await db.commit()
