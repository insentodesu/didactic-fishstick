"""
Клиент для получения данных кассового чека по QR-коду.

QR-код фискального чека содержит строку вида:
  t=20231015T143200&s=1234.56&fn=1234567890123456&i=12345&fp=123456789&n=1

Параметры:
  t  — дата и время (YYYYMMDDTHHmmss)
  s  — сумма чека (рубли, точка как разделитель)
  fn — номер фискального накопителя (16 цифр)
  i  — номер фискального документа
  fp — фискальный признак (подпись)
  n  — признак расчёта (1 = приход, 2 = возврат и тд)

Провайдер: proverkacheka.com — агрегатор ФНС данных.
  API ключ: зарегистрироваться на proverkacheka.com → Личный кабинет → API
  Стоимость: ~1.5₽ за детальный запрос (есть пробный период).

Режим без ключа: возвращает данные, разобранные из QR-кода (без списка позиций).
"""

import re
from datetime import datetime

import httpx

from app.config import settings


# ============================================================
# Парсинг QR-строки
# ============================================================

def parse_qr_string(qr_raw: str) -> dict:
    """
    Парсит строку или URL из QR-кода фискального чека.
    Поддерживает форматы:
      - t=...&s=...&fn=...&i=...&fp=...&n=...
      - https://example.com/?t=...&s=...
    """
    raw = qr_raw.strip()
    if "?" in raw:
        raw = raw.split("?", 1)[1]

    params: dict[str, str] = {}
    for part in raw.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            params[k.lower().strip()] = v.strip()

    fn = params.get("fn")
    fd = params.get("i") or params.get("fd")
    fp = params.get("fp")
    raw_sum = params.get("s", "0").replace(",", ".")
    raw_date = params.get("t", "")

    purchase_date = None
    if raw_date:
        for fmt in ("%Y%m%dT%H%M%S", "%Y%m%dT%H%M", "%Y-%m-%dT%H:%M:%S"):
            try:
                purchase_date = datetime.strptime(raw_date, fmt).isoformat()
                break
            except ValueError:
                continue

    return {
        "fn": fn,
        "fd": fd,
        "fp": fp,
        "sum": raw_sum,
        "date": raw_date,
        "purchase_date_iso": purchase_date,
        "operation_type": params.get("n", "1"),
        "raw_params": params,
    }


def validate_qr_params(parsed: dict) -> tuple[bool, str]:
    """Базовая валидация параметров QR без обращения к API."""
    fn, fd, fp = parsed.get("fn"), parsed.get("fd"), parsed.get("fp")
    if not fn or not fd or not fp:
        return False, "QR-код не содержит обязательных параметров (fn, i, fp)"
    if not re.fullmatch(r"\d{16}", fn):
        return False, f"Некорректный номер ФН: должен содержать 16 цифр, получено '{fn}'"
    if not re.fullmatch(r"\d+", fd):
        return False, f"Некорректный номер ФД: '{fd}'"
    if not re.fullmatch(r"\d+", fp):
        return False, f"Некорректный ФП: '{fp}'"
    return True, "ok"


# ============================================================
# Запрос к proverkacheka.com API
# ============================================================

async def fetch_receipt_from_fns(
    fn: str,
    fd: str,
    fp: str,
    amount: str = "0",
    date: str = "",
    operation_type: str = "1",
) -> dict | None:
    """
    Получает полную детализацию чека через proverkacheka.com API.
    Возвращает None если API недоступен или ключ не задан.

    Документация: https://proverkacheka.com (раздел API в личном кабинете)
    """
    if not settings.fns_client_secret:
        return None

    payload = {
        "fn": fn,
        "fd": fd,
        "fp": fp,
        "n": int(operation_type),
        "s": amount,
        "t": date,
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{settings.fns_api_url}/check/get",
                json=payload,
                headers={
                    "clientSecret": settings.fns_client_secret,
                    "Content-Type": "application/json",
                },
            )
    except httpx.RequestError:
        return None

    if resp.status_code != 200:
        return None

    try:
        data = resp.json()
    except Exception:
        return None

    # Проверяем код ответа proverkacheka (1 = успех)
    if data.get("code") != 1:
        return None

    # Путь к данным чека в ответе API
    ticket = (
        data.get("data", {})
        .get("json", {})
        .get("ticket", {})
        .get("document", {})
        .get("receipt", {})
    )

    # Альтернативный путь (API v1 иногда возвращает иначе)
    if not ticket:
        ticket = data.get("data", {}).get("json", {})

    if not ticket:
        return None

    items = [
        {
            "name": item.get("name", ""),
            "price": round(item.get("price", 0) / 100, 2),       # копейки → рубли
            "quantity": item.get("quantity", 1),
            "sum": round(item.get("sum", 0) / 100, 2),
            "nds_type": item.get("ndsType"),
        }
        for item in ticket.get("items", [])
    ]

    raw_date = ticket.get("dateTime") or ticket.get("localDateTime")
    purchase_date = None
    if raw_date:
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y%m%dT%H%M%S", "%Y%m%dT%H%M"):
            try:
                purchase_date = datetime.strptime(str(raw_date), fmt).isoformat()
                break
            except (ValueError, TypeError):
                continue

    return {
        "seller_name": ticket.get("user") or ticket.get("userInn", ""),
        "seller_inn": ticket.get("userInn", ""),
        "seller_address": ticket.get("retailPlaceAddress") or ticket.get("address", ""),
        "cashier": ticket.get("operator"),
        "kkt_reg_number": ticket.get("kktRegId"),
        "total_amount": round(ticket.get("totalSum", 0) / 100, 2),
        "cash_amount": round(ticket.get("cashTotalSum", 0) / 100, 2),
        "card_amount": round(ticket.get("ecashTotalSum", 0) / 100, 2),
        "nds_total": round(ticket.get("nds18", 0) / 100, 2),
        "purchase_date": purchase_date,
        "fiscal_drive_number": ticket.get("fiscalDriveNumber") or fn,
        "fiscal_document_number": ticket.get("fiscalDocumentNumber") or fd,
        "fiscal_sign": ticket.get("fiscalSign") or fp,
        "items": items,
        "items_count": len(items),
        "source": "proverkacheka",
    }


# ============================================================
# Публичная точка входа
# ============================================================

async def get_receipt_data(qr_raw: str) -> dict:
    """
    Главная функция. Парсит QR, валидирует, запрашивает API.
    Всегда возвращает словарь (никогда не падает).

    Поля в ответе:
      - valid: bool — прошёл ли QR валидацию
      - has_details: bool — удалось ли получить полную детализацию
      - parsed: dict — данные из QR (всегда есть)
      - details: dict | None — полные данные чека от API
      - error: str | None — описание ошибки
    """
    parsed = parse_qr_string(qr_raw)
    valid, validation_msg = validate_qr_params(parsed)

    if not valid:
        return {
            "valid": False,
            "has_details": False,
            "parsed": parsed,
            "details": None,
            "error": validation_msg,
        }

    details = await fetch_receipt_from_fns(
        fn=parsed["fn"],
        fd=parsed["fd"],
        fp=parsed["fp"],
        amount=parsed.get("sum", "0"),
        date=parsed.get("date", ""),
        operation_type=parsed.get("operation_type", "1"),
    )

    return {
        "valid": True,
        "has_details": details is not None,
        "parsed": {
            "fn": parsed["fn"],
            "fd": parsed["fd"],
            "fp": parsed["fp"],
            "amount": float(parsed.get("sum", 0) or 0),
            "purchase_date": parsed.get("purchase_date_iso"),
        },
        "details": details,
        "error": None if details else (
            "Детализация чека недоступна: API ключ не задан. "
            "Зарегистрируйтесь на proverkacheka.com для получения ключа."
            if not settings.fns_client_secret
            else "Не удалось получить данные от ФНС. Чек может не существовать или произошла ошибка API."
        ),
    }
