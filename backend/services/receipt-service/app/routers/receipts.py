import json
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.deps import get_current_user_id
from app.services.fns_client import get_receipt_data

router = APIRouter(prefix="/receipts", tags=["Чеки"])


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
