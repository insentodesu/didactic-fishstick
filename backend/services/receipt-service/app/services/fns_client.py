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

Провайдеры:
  1. proverkacheka.com — платный агрегатор ФНС (~1.5₽/запрос, есть пробный период)
  2. nalog.ru FNS mobile API — бесплатный, требует sessionId
     Получить sessionId: https://lkfl2.nalog.ru или через приложение «Проверка чека ФНС»
     Установите переменную окружения NALOG_SESSION_ID
"""

import os
import re
import uuid
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

    if data.get("code") != 1:
        return None

    ticket = (
        data.get("data", {})
        .get("json", {})
        .get("ticket", {})
        .get("document", {})
        .get("receipt", {})
    )

    if not ticket:
        ticket = data.get("data", {}).get("json", {})

    if not ticket:
        return None

    return _parse_ticket_dict(ticket, fn, fd, fp, source="proverkacheka")


# ============================================================
# Запрос к lkdr.nalog.ru (официальный кабинет ФНС, Bearer-токен)
# ============================================================

_LKDR_BASE = "https://lkdr.nalog.ru"


async def fetch_receipt_lkdr(fn: str, fd: str, fp: str) -> dict | None:
    """
    Получает полную детализацию чека через lkdr.nalog.ru.

    Алгоритм:
      1. POST /api/v1/receipt {fn, fd} → список чеков, берём key
      2. POST /api/v1/receipt/fiscal_data {key} → полные данные с позициями

    Требует переменную окружения NALOG_LKDR_TOKEN (Bearer JWT из lkdr.nalog.ru).
    Получить: открыть lkdr.nalog.ru → DevTools → любой /api запрос → заголовок Authorization.
    Токен действует ~1 час, обновляется автоматически при новом логине.
    """
    token = settings.nalog_lkdr_token
    if not token:
        return None

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            # Шаг 1: найти чек по fn+fd
            r1 = await client.post(
                f"{_LKDR_BASE}/api/v1/receipt",
                json={"fiscalDriveNumber": fn, "fiscalDocumentNumber": fd},
                headers=headers,
            )
            if r1.status_code != 200:
                return None

            receipts = r1.json().get("receipts", [])
            if not receipts:
                return None

            # Берём первый совпавший чек (fn+fd должны совпасть)
            key = None
            for r in receipts:
                if str(r.get("fiscalDriveNumber")) == fn and str(r.get("fiscalDocumentNumber")) == fd:
                    key = r.get("key")
                    break
            if not key:
                key = receipts[0].get("key")
            if not key:
                return None

            # Шаг 2: полная детализация по key
            r2 = await client.post(
                f"{_LKDR_BASE}/api/v1/receipt/fiscal_data",
                json={"key": key},
                headers=headers,
            )
            if r2.status_code != 200:
                return None

            data = r2.json()
            return _parse_lkdr_receipt(data, fn, fd, fp)

    except Exception:
        return None


def _parse_lkdr_receipt(data: dict, fn: str, fd: str, fp: str) -> dict:
    """Нормализует ответ lkdr.nalog.ru в общий формат. Суммы уже в рублях."""
    items = [
        {
            "name": item.get("name", ""),
            "price": float(item.get("price", 0)),
            "quantity": float(item.get("quantity", 1)),
            "sum": float(item.get("sum", 0)),
            "nds_type": item.get("nds"),
        }
        for item in data.get("items", [])
    ]

    raw_date = data.get("dateTime")
    purchase_date = None
    if raw_date:
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y%m%dT%H%M%S", "%Y%m%dT%H%M"):
            try:
                purchase_date = datetime.strptime(str(raw_date), fmt).isoformat()
                break
            except (ValueError, TypeError):
                continue

    return {
        "seller_name": data.get("user", ""),
        "seller_inn": (data.get("userInn") or "").strip(),
        "seller_address": data.get("retailPlaceAddress") or data.get("retailPlace", ""),
        "cashier": data.get("operator"),
        "kkt_reg_number": (data.get("kktRegId") or "").strip(),
        "total_amount": float(data.get("totalSum", 0)),
        "cash_amount": float(data.get("cashTotalSum", 0)),
        "card_amount": float(data.get("ecashTotalSum", 0)),
        "nds_total": 0.0,
        "purchase_date": purchase_date,
        "fiscal_drive_number": str(data.get("fiscalDriveNumber") or fn),
        "fiscal_document_number": str(data.get("fiscalDocumentNumber") or fd),
        "fiscal_sign": str(data.get("fiscalSign") or fp),
        "items": items,
        "items_count": len(items),
        "source": "lkdr.nalog.ru",
    }


# ============================================================
# Запрос к nalog.ru FNS mobile API
# ============================================================

_NALOG_BASE = "https://irkkt-mobile.nalog.ru:8888"

_NALOG_HEADERS = {
    "clientVersion": "2.9.0",
    "Device-Id": str(uuid.UUID("7c82010f-16cc-446b-8f66-fc2da4de2445")).upper(),
    "Device-OS": "Android",
    "Accept": "application/json",
    "Content-Type": "application/json",
}


async def _nalog_get_session(inn: str, password: str) -> str | None:
    """Получает sessionId по ИНН и паролю от lkfl.nalog.ru."""
    try:
        async with httpx.AsyncClient(timeout=15.0, verify=False) as client:
            resp = await client.post(
                f"{_NALOG_BASE}/v2/mobile/users/lkfl/auth",
                json={"inn": inn, "client_secret": password, "os": "android"},
                headers=_NALOG_HEADERS,
            )
            if resp.status_code == 200:
                return resp.json().get("sessionId")
    except Exception:
        pass
    return None


async def fetch_receipt_nalog_ru(
    fn: str,
    fd: str,
    fp: str,
    date: str = "",
    amount: str = "0",
) -> dict | None:
    """
    Получает детализацию чека через официальный API ФНС (nalog.ru).

    Требует одно из:
      - Переменная окружения NALOG_SESSION_ID (sessionId из приложения «Проверка чека ФНС»)
      - Переменные NALOG_INN + NALOG_PASSWORD (ИНН и пароль от lkfl.nalog.ru)

    Если ни одно не задано — возвращает None.
    """
    session_id = os.environ.get("NALOG_SESSION_ID", "")

    # Попытка получить сессию по ИНН+паролю, если sessionId не задан
    if not session_id:
        inn = os.environ.get("NALOG_INN", "")
        password = os.environ.get("NALOG_PASSWORD", "")
        if inn and password:
            session_id = await _nalog_get_session(inn, password) or ""

    if not session_id:
        return None

    # Формируем строку QR для lookup
    qr_string = f"t={date}&s={amount}&fn={fn}&i={fd}&fp={fp}&n=1"

    try:
        async with httpx.AsyncClient(timeout=15.0, verify=False) as client:
            resp = await client.post(
                f"{_NALOG_BASE}/v2/ticket",
                json={"qr": qr_string},
                headers={**_NALOG_HEADERS, "sessionId": session_id},
            )
            if resp.status_code == 401:
                # Сессия истекла — сбрасываем, но ничего не можем сделать без авторизации
                return None
            if resp.status_code != 200:
                return None

            data = resp.json()
            ticket = (
                data.get("ticket", {})
                .get("document", {})
                .get("receipt", {})
            )
            if not ticket:
                return None
            return _parse_ticket_dict(ticket, fn, fd, fp, source="nalog.ru")
    except Exception:
        return None


# ============================================================
# Общий парсер структуры чека
# ============================================================

def _parse_ticket_dict(ticket: dict, fn: str, fd: str, fp: str, source: str) -> dict:
    """Нормализует словарь чека из разных источников в единый формат."""
    items = [
        {
            "name": item.get("name", ""),
            "price": round(item.get("price", 0) / 100, 2),
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
        "source": source,
    }


# ============================================================
# Публичная точка входа
# ============================================================

async def get_receipt_data(qr_raw: str) -> dict:
    """
    Главная функция. Парсит QR, валидирует, запрашивает API.
    Всегда возвращает словарь (никогда не падает).

    Порядок попыток:
      1. proverkacheka.com (если задан FNS_CLIENT_SECRET)
      2. nalog.ru FNS API (если задан NALOG_SESSION_ID или NALOG_INN+NALOG_PASSWORD)
      3. Только данные из QR (без позиций)

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

    fn = parsed["fn"]
    fd = parsed["fd"]
    fp = parsed["fp"]
    amount = parsed.get("sum", "0")
    date = parsed.get("date", "")
    op = parsed.get("operation_type", "1")

    # Попытка 1: proverkacheka.com
    details = await fetch_receipt_from_fns(fn=fn, fd=fd, fp=fp, amount=amount, date=date, operation_type=op)

    # Попытка 2: lkdr.nalog.ru (NALOG_LKDR_TOKEN)
    if details is None:
        details = await fetch_receipt_lkdr(fn=fn, fd=fd, fp=fp)

    # Попытка 3: nalog.ru mobile API (NALOG_SESSION_ID)
    if details is None:
        details = await fetch_receipt_nalog_ru(fn=fn, fd=fd, fp=fp, date=date, amount=amount)

    # Формируем сообщение об ошибке при отсутствии детализации
    if details is None:
        has_proverkacheka = bool(settings.fns_client_secret)
        has_nalog = bool(
            os.environ.get("NALOG_SESSION_ID")
            or (os.environ.get("NALOG_INN") and os.environ.get("NALOG_PASSWORD"))
        )
        if not has_proverkacheka and not has_nalog:
            error_msg = (
                "Детализация чека недоступна. Для получения списка позиций задайте "
                "одну из переменных окружения: FNS_CLIENT_SECRET (proverkacheka.com) "
                "или NALOG_SESSION_ID (nalog.ru)."
            )
        else:
            error_msg = "Не удалось получить данные от ФНС. Чек может не существовать или произошла ошибка API."
    else:
        error_msg = None

    return {
        "valid": True,
        "has_details": details is not None,
        "parsed": {
            "fn": fn,
            "fd": fd,
            "fp": fp,
            "amount": float(amount or 0),
            "purchase_date": parsed.get("purchase_date_iso"),
        },
        "details": details,
        "error": error_msg,
    }
