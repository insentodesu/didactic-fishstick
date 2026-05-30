"""
Детектор подписок из транзакций.
Алгоритм: находит транзакции с одинаковым мерчантом,
повторяющиеся с интервалом ~30 дней (±5) или ~7 дней (±2).
"""

import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal


# Известные подписочные сервисы с нормализованными именами
KNOWN_SUBSCRIPTIONS = {
    r"яндекс.?плюс|yandex\s*plus": ("Яндекс Плюс", "monthly", "🎵"),
    r"spotify": ("Spotify", "monthly", "🎵"),
    r"netflix": ("Netflix", "monthly", "🎬"),
    r"okko": ("Okko", "monthly", "🎬"),
    r"ivi": ("Иви", "monthly", "🎬"),
    r"premier": ("Premier", "monthly", "🎬"),
    r"more\.?tv": ("More.TV", "monthly", "🎬"),
    r"telegram\s*premium": ("Telegram Premium", "monthly", "💬"),
    r"vk\s*combo|vk\s*music": ("VK Комбо", "monthly", "🎵"),
    r"сбер\s*прайм|sber\s*prime": ("Сбер Прайм", "monthly", "🛒"),
    r"skillbox": ("Skillbox", "monthly", "📚"),
    r"geekbrains": ("GeekBrains", "monthly", "📚"),
    r"1с": ("1С", "yearly", "💼"),
    r"adobe": ("Adobe CC", "monthly", "🎨"),
    r"apple\.com/bill|apple\s*subscr": ("Apple Подписка", "monthly", "🍎"),
    r"google\s*storage|google\s*one": ("Google One", "monthly", "☁️"),
}


@dataclass
class DetectedSubscription:
    merchant_name: str
    canonical_name: str
    amount: Decimal
    billing_period: str
    logo_emoji: str
    last_billing_date: date
    next_billing_date: date
    confidence: float
    occurrences: int


def normalize_merchant(merchant: str) -> str:
    return re.sub(r"\s+", " ", merchant.lower().strip())


def detect_known_subscription(merchant: str) -> tuple[str, str, str] | None:
    norm = normalize_merchant(merchant)
    for pattern, (name, period, emoji) in KNOWN_SUBSCRIPTIONS.items():
        if re.search(pattern, norm, re.I):
            return name, period, emoji
    return None


def detect_recurring(transactions: list[dict]) -> list[DetectedSubscription]:
    """
    Анализирует список транзакций и находит регулярные платежи.
    transactions: [{merchant_name, amount, transaction_date}, ...]
    """
    by_merchant: dict[str, list[dict]] = defaultdict(list)
    for tx in transactions:
        if tx.get("is_income"):
            continue
        key = normalize_merchant(tx.get("merchant_name", ""))
        by_merchant[key].append(tx)

    detected = []

    for merchant, txs in by_merchant.items():
        if len(txs) < 2:
            continue

        txs_sorted = sorted(txs, key=lambda t: t["transaction_date"])
        amounts = [Decimal(str(t["amount"])) for t in txs_sorted]

        # Проверяем однородность суммы (±10%)
        avg_amount = sum(amounts) / len(amounts)
        if any(abs(a - avg_amount) / avg_amount > 0.15 for a in amounts):
            continue

        # Рассчитываем интервалы между транзакциями
        dates = [t["transaction_date"] for t in txs_sorted]
        intervals = [(dates[i+1] - dates[i]).days for i in range(len(dates)-1)]
        avg_interval = sum(intervals) / len(intervals)

        if 25 <= avg_interval <= 35:
            period = "monthly"
        elif 5 <= avg_interval <= 9:
            period = "weekly"
        elif 360 <= avg_interval <= 370:
            period = "yearly"
        else:
            continue

        last_date = dates[-1]
        next_date = last_date + timedelta(days=30 if period == "monthly" else 7 if period == "weekly" else 365)

        known = detect_known_subscription(txs[0].get("merchant_name", ""))
        canonical = known[0] if known else txs[0].get("merchant_name", merchant)[:255]
        emoji = known[2] if known else "📱"
        confidence = 0.95 if known else min(0.5 + len(txs) * 0.1, 0.85)

        detected.append(DetectedSubscription(
            merchant_name=txs[0].get("merchant_name", merchant),
            canonical_name=canonical,
            amount=avg_amount,
            billing_period=period,
            logo_emoji=emoji,
            last_billing_date=last_date,
            next_billing_date=next_date,
            confidence=confidence,
            occurrences=len(txs),
        ))

    return detected
