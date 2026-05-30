"""
Парсер банковских выписок.
Поддерживаемые форматы:
  - Сбербанк: CSV (кодировка windows-1251)
  - Тинькофф: CSV (UTF-8)
  - ВТБ: XLS/XLSX
  - Альфа-Банк: CSV/XLS
  - Общий PDF (pdfplumber, лучшее усилие)
"""

import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from io import BytesIO
from pathlib import Path

import pdfplumber
import pandas as pd


@dataclass
class RawTransaction:
    transaction_date: date
    amount: Decimal
    is_income: bool
    merchant_name: str
    description: str
    external_id: str | None = None


def detect_bank(df: pd.DataFrame) -> str:
    """Определяет банк по набору колонок в выписке."""
    cols = set(c.lower() for c in df.columns)
    if {"дата операции", "сумма в валюте счёта", "статус"} & cols:
        return "tinkoff"
    if {"дата", "сумма", "описание операции", "счёт списания"} & cols:
        return "sber"
    if {"date", "transaction amount", "merchant name"} & cols:
        return "vtb"
    if {"дата", "сумма", "наименование"} & cols:
        return "alfa"
    return "unknown"


def parse_csv_tinkoff(df: pd.DataFrame) -> list[RawTransaction]:
    results = []
    for _, row in df.iterrows():
        try:
            raw_date = str(row.get("Дата операции", "")).strip()
            tx_date = pd.to_datetime(raw_date, dayfirst=True).date()

            raw_amount = str(row.get("Сумма операции", "0")).replace(" ", "").replace(",", ".")
            amount = Decimal(raw_amount)
            is_income = amount > 0

            merchant = str(row.get("Описание", "")).strip()
            ext_id = str(row.get("Номер операции", "")).strip() or None

            results.append(RawTransaction(
                transaction_date=tx_date,
                amount=abs(amount),
                is_income=is_income,
                merchant_name=merchant[:500],
                description=merchant,
                external_id=ext_id,
            ))
        except Exception:
            continue
    return results


def parse_csv_sber(df: pd.DataFrame) -> list[RawTransaction]:
    results = []
    for _, row in df.iterrows():
        try:
            tx_date = pd.to_datetime(str(row.get("Дата", "")).strip(), dayfirst=True).date()
            raw_amount = str(row.get("Сумма", "0")).replace(" ", "").replace(",", ".").replace("−", "-")
            amount = Decimal(raw_amount)
            is_income = amount > 0
            merchant = str(row.get("Описание операции", "")).strip()

            results.append(RawTransaction(
                transaction_date=tx_date,
                amount=abs(amount),
                is_income=is_income,
                merchant_name=merchant[:500],
                description=merchant,
            ))
        except Exception:
            continue
    return results


def parse_xlsx_vtb(df: pd.DataFrame) -> list[RawTransaction]:
    results = []
    for _, row in df.iterrows():
        try:
            tx_date = pd.to_datetime(row.get("Дата")).date()
            amount = Decimal(str(row.get("Сумма", 0)))
            is_income = amount > 0
            merchant = str(row.get("Получатель/Плательщик", "")).strip()

            results.append(RawTransaction(
                transaction_date=tx_date,
                amount=abs(amount),
                is_income=is_income,
                merchant_name=merchant[:500],
                description=str(row.get("Назначение платежа", "")).strip(),
            ))
        except Exception:
            continue
    return results


def parse_pdf_generic(content: bytes) -> list[RawTransaction]:
    """
    Парсинг PDF лучшим усилием.
    Ищет строки вида: DD.MM.YYYY ... -1234.56 или +1234.56
    """
    results = []
    date_pattern = re.compile(r"\b(\d{2}\.\d{2}\.\d{4})\b")
    amount_pattern = re.compile(r"([+-]?\d[\d\s]*[,.]?\d{2})\s*(?:руб|RUB)?")

    with pdfplumber.open(BytesIO(content)) as pdf:
        for page in pdf.pages:
            text = page.extract_text() or ""
            for line in text.splitlines():
                dates = date_pattern.findall(line)
                amounts = amount_pattern.findall(line)
                if not dates or not amounts:
                    continue
                try:
                    tx_date = pd.to_datetime(dates[0], dayfirst=True).date()
                    raw = amounts[-1].replace(" ", "").replace(",", ".")
                    amount = Decimal(raw)
                    is_income = amount > 0
                    merchant = line[:200].strip()

                    results.append(RawTransaction(
                        transaction_date=tx_date,
                        amount=abs(amount),
                        is_income=is_income,
                        merchant_name=merchant,
                        description=line.strip(),
                    ))
                except Exception:
                    continue
    return results


def parse_statement(file_content: bytes, filename: str) -> tuple[list[RawTransaction], str]:
    """
    Главная точка входа. Возвращает (транзакции, название_банка).
    """
    ext = Path(filename).suffix.lower()

    if ext == ".pdf":
        return parse_pdf_generic(file_content), "pdf_generic"

    if ext in {".xls", ".xlsx"}:
        df = pd.read_excel(BytesIO(file_content), dtype=str)
        bank = detect_bank(df)
        if bank == "vtb":
            return parse_xlsx_vtb(df), "vtb"
        # Пробуем общий парсер для Excel
        return parse_xlsx_vtb(df), bank

    if ext == ".csv":
        # Пробуем UTF-8, потом windows-1251 (Сбер)
        for enc in ("utf-8", "windows-1251", "utf-8-sig"):
            try:
                df = pd.read_csv(BytesIO(file_content), encoding=enc, sep=None, engine="python", dtype=str)
                break
            except Exception:
                continue
        else:
            raise ValueError("Не удалось прочитать CSV: неизвестная кодировка")

        bank = detect_bank(df)
        if bank == "tinkoff":
            return parse_csv_tinkoff(df), "tinkoff"
        if bank == "sber":
            return parse_csv_sber(df), "sber"
        return parse_csv_tinkoff(df), "unknown"

    raise ValueError(f"Неподдерживаемый формат файла: {ext}")
