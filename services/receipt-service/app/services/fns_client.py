"""
Клиент ФНС API (proverkacheka.com) для расшифровки QR-кодов с кассовых чеков.
QR-код кассового чека содержит строку вида:
  t=20231015T143200&s=1234.56&fn=1234567890123456&i=12345&fp=123456789&n=1
"""

import re
from urllib.parse import parse_qs, urlparse

import httpx

from app.config import settings


def parse_qr_string(qr_raw: str) -> dict:
    """Парсит строку из QR-кода чека."""
    params = {}
    # Поддерживаем и query-string и URL форматы
    if "?" in qr_raw:
        qr_raw = qr_raw.split("?", 1)[1]
    for part in qr_raw.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            params[k.lower()] = v
    return {
        "fn": params.get("fn"),
        "fd": params.get("i"),
        "fp": params.get("fp"),
        "sum": params.get("s"),
        "date": params.get("t"),
        "type": params.get("n"),
    }


async def fetch_receipt_from_fns(fn: str, fd: str, fp: str) -> dict | None:
    """Получает детализацию чека от ФНС через proverkacheka.com."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            f"{settings.fns_api_url}/check/get",
            json={"fn": fn, "fd": fd, "fp": fp, "n": 1},
            headers={"clientSecret": settings.fns_client_secret},
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
        ticket = data.get("data", {}).get("json", {}).get("ticket", {}).get("document", {}).get("receipt", {})
        if not ticket:
            return None

        items = [
            {
                "name": item.get("name", ""),
                "price": item.get("price", 0) / 100,
                "quantity": item.get("quantity", 1),
                "sum": item.get("sum", 0) / 100,
            }
            for item in ticket.get("items", [])
        ]

        return {
            "seller_name": ticket.get("user", ""),
            "seller_inn": ticket.get("userInn", ""),
            "seller_address": ticket.get("retailPlaceAddress", ""),
            "total_amount": ticket.get("totalSum", 0) / 100,
            "purchase_date": ticket.get("dateTime"),
            "items": items,
        }
