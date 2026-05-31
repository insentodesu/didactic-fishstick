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

import asyncio
import base64
import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


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
_LKDR_TOKEN_CACHE_FILE = "/tmp/nalog_lkdr_tokens.json"

# Модульный кэш токенов (живёт в памяти процесса)
_lkdr_access_token: str = ""
_lkdr_refresh_token: str = ""
_token_refresh_lock = asyncio.Lock()


def _jwt_payload(token: str) -> dict:
    """Декодирует payload JWT без проверки подписи."""
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part))
    except Exception:
        return {}


def _token_is_expired(token: str, buffer_seconds: int = 300) -> bool:
    """Возвращает True, если JWT уже истёк или истечёт через buffer_seconds."""
    exp = _jwt_payload(token).get("exp", 0)
    if not exp:
        return True
    return datetime.now(timezone.utc).timestamp() > exp - buffer_seconds


def _extract_device_id(refresh_token: str) -> str:
    """Извлекает deviceId из payload refresh-токена."""
    try:
        sub = _jwt_payload(refresh_token).get("sub", "")
        ctx = json.loads(sub)
        return ctx.get("refreshContext", {}).get("deviceId", "")
    except Exception:
        return ""


def _load_cached_tokens() -> tuple[str, str]:
    """Читает токены из файлового кэша (переживает рестарт контейнера)."""
    try:
        with open(_LKDR_TOKEN_CACHE_FILE) as f:
            d = json.load(f)
            return d.get("access_token", ""), d.get("refresh_token", "")
    except Exception:
        return "", ""


def _save_cached_tokens(access: str, refresh: str) -> None:
    """Сохраняет токены в файловый кэш."""
    try:
        with open(_LKDR_TOKEN_CACHE_FILE, "w") as f:
            json.dump({"access_token": access, "refresh_token": refresh}, f)
    except Exception:
        pass


def _init_lkdr_tokens() -> None:
    """Инициализирует кэш токенов из env или файла при первом обращении."""
    global _lkdr_access_token, _lkdr_refresh_token

    # Приоритет: файловый кэш (свежее обновлённые) → env
    cached_access, cached_refresh = _load_cached_tokens()

    _lkdr_access_token = cached_access or settings.nalog_lkdr_token
    _lkdr_refresh_token = cached_refresh or settings.nalog_lkdr_refresh_token


async def _refresh_lkdr_token() -> bool:
    """
    Обменивает refresh-token на новую пару access/refresh.
    Обновляет модульный кэш и файловый кэш.
    Возвращает True при успехе.
    """
    global _lkdr_access_token, _lkdr_refresh_token

    refresh = _lkdr_refresh_token or settings.nalog_lkdr_refresh_token
    if not refresh:
        logger.warning("nalog lkdr: refresh token не задан")
        return False

    device_id = _extract_device_id(refresh)
    payload = {
        "refreshToken": refresh,
        "deviceInfo": {
            "sourceDeviceId": device_id,
            "sourceType": "WEB",
            "appVersion": "1.0.0",
            "metaDetails": {
                "userAgent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Safari/605.1.15"
                )
            },
        },
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{_LKDR_BASE}/api/v1/auth/token",
                json=payload,
                headers={"Content-Type": "application/json", "Accept": "application/json"},
            )
        if resp.status_code != 200:
            logger.error("nalog lkdr: не удалось обновить токен, статус %s: %s", resp.status_code, resp.text[:200])
            return False

        data = resp.json()
        new_access = data.get("token", "")
        new_refresh = data.get("refreshToken", "") or refresh  # fallback на старый
        expires_in = data.get("tokenExpireIn", "unknown")

        if not new_access:
            return False

        _lkdr_access_token = new_access
        _lkdr_refresh_token = new_refresh
        _save_cached_tokens(new_access, new_refresh)
        logger.info("nalog lkdr: токен обновлён, истекает %s", expires_in)
        return True

    except Exception as exc:
        logger.error("nalog lkdr: ошибка при обновлении токена: %s", exc)
        return False


async def _get_valid_lkdr_token() -> str:
    """
    Возвращает актуальный access-токен, при необходимости обновляет через refresh.
    Защищено async-локом от параллельных рефрешей.
    """
    global _lkdr_access_token, _lkdr_refresh_token

    if not _lkdr_access_token and not _lkdr_refresh_token:
        _init_lkdr_tokens()

    if _lkdr_access_token and not _token_is_expired(_lkdr_access_token):
        return _lkdr_access_token

    async with _token_refresh_lock:
        # Проверяем ещё раз под локом — другой корутин мог уже обновить
        if _lkdr_access_token and not _token_is_expired(_lkdr_access_token):
            return _lkdr_access_token

        logger.info("nalog lkdr: access-токен истёк, обновляем через refresh token…")
        await _refresh_lkdr_token()
        return _lkdr_access_token


async def fetch_receipt_lkdr(fn: str, fd: str, fp: str, receipt_date: str | None = None) -> dict | None:
    """
    Получает полную детализацию чека через lkdr.nalog.ru.

    Алгоритм:
      1. Получаем/обновляем Bearer-токен (авто-рефреш при истечении)
      2. POST /api/v1/receipt {fn, fd} → список чеков, берём key
      3. POST /api/v1/receipt/fiscal_data {key} → полные данные с позициями

    Токены хранятся в памяти и /tmp/nalog_lkdr_tokens.json.
    Для старта нужна пара NALOG_LKDR_TOKEN + NALOG_LKDR_REFRESH_TOKEN в .env.
    """
    if not settings.nalog_lkdr_token and not settings.nalog_lkdr_refresh_token:
        return None

    token = await _get_valid_lkdr_token()
    if not token:
        return None

    async def _find_receipt_key(client: httpx.AsyncClient, headers: dict) -> str | None:
        """
        Ищет ключ чека по fn/fd через пагинацию (до 50 страниц).

        API возвращает ВСЕ чеки пользователя (10 шт. на страницу, от новых к старым).
        Ранняя остановка: если даты на текущей странице ушли раньше даты чека,
        дальше смотреть бессмысленно.

        receipt_date — дата чека из QR (ISO-строка или YYYYMMDD…) для оптимизации.
        """
        _MAX_PAGES = 50

        # Нормализуем дату для сравнения (первые 10 символов: YYYY-MM-DD)
        target_date_prefix: str | None = None
        if receipt_date:
            # ISO: "2025-01-15T12:00:00" → "2025-01-15"
            # или "20250115T120000" → нормализуем
            d = receipt_date.replace("T", "-").replace("t", "-")
            if len(d) >= 8 and "-" not in d[:8]:
                # Compact YYYYMMDD → YYYY-MM-DD
                target_date_prefix = f"{d[:4]}-{d[4:6]}-{d[6:8]}"
            else:
                target_date_prefix = d[:10]

        for page in range(_MAX_PAGES):
            offset = page * 10
            payload: dict = {"fiscalDriveNumber": fn, "fiscalDocumentNumber": fd}
            if offset > 0:
                payload["offset"] = offset

            r = await client.post(
                f"{_LKDR_BASE}/api/v1/receipt",
                json=payload,
                headers=headers,
            )
            if r.status_code == 401:
                return "__401__"
            if r.status_code != 200:
                return None

            data = r.json()
            receipts = data.get("receipts", [])

            for rec in receipts:
                if (
                    str(rec.get("fiscalDriveNumber", "")) == fn
                    and str(rec.get("fiscalDocumentNumber", "")) == fd
                ):
                    key = rec.get("key")
                    logger.info(
                        "nalog lkdr: чек fn=%s fd=%s найден на стр.%d, key=%s…",
                        fn, fd, page + 1, str(key)[:30],
                    )
                    return key

            if not data.get("hasMore"):
                break

            # Ранняя остановка: если самый старый чек на странице раньше искомого
            if target_date_prefix and receipts:
                oldest = str(receipts[-1].get("createdDate", ""))[:10]
                if oldest and oldest < target_date_prefix:
                    logger.info(
                        "nalog lkdr: ранняя остановка на стр.%d (дата страницы %s < целевой %s)",
                        page + 1, oldest, target_date_prefix,
                    )
                    break

        logger.warning(
            "nalog lkdr: чек fn=%s fd=%s не найден в аккаунте lkdr (проверено стр.%d)",
            fn, fd, min(page + 1, _MAX_PAGES),
        )
        return None

    async def _do_request(bearer: str) -> dict | None:
        headers = {
            "Authorization": f"Bearer {bearer}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        async with httpx.AsyncClient(timeout=20.0) as client:
            key = await _find_receipt_key(client, headers)

            if key == "__401__":
                return None  # сигнал для рефреша
            if not key:
                return False  # чек не найден — не показываем чужой

            r2 = await client.post(
                f"{_LKDR_BASE}/api/v1/receipt/fiscal_data",
                json={"key": key},
                headers=headers,
            )
            if r2.status_code != 200:
                return False

            return _parse_lkdr_receipt(r2.json(), fn, fd, fp)

    try:
        result = await _do_request(token)

        # 401 → пробуем принудительно обновить токен и повторить один раз
        if result is None:
            logger.info("nalog lkdr: получен 401, принудительно обновляем токен…")
            refreshed = await _refresh_lkdr_token()
            if not refreshed or not _lkdr_access_token:
                return None
            result = await _do_request(_lkdr_access_token)

        return result if result else None

    except Exception as exc:
        logger.error("nalog lkdr: неожиданная ошибка: %s", exc)
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
        details = await fetch_receipt_lkdr(fn=fn, fd=fd, fp=fp, receipt_date=parsed.get("purchase_date_iso") or parsed.get("date"))

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
