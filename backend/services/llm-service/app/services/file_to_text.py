"""
Конвертер файлов выписок → текст для передачи в LLM.

AIESA не принимает файлы напрямую, поэтому:
  1. Парсим файл локально (pandas / pdfplumber)
  2. Формируем компактное текстовое представление
  3. Передаём в AIESA как часть промпта

Стратегия сжатия (чтобы уложиться в контекст):
  - Группируем по мерчанту: имя + сумма + количество
  - Добавляем сводку: доходы, расходы, период
  - Максимум ~4000 токенов контекста транзакций
"""

import re
from decimal import Decimal, InvalidOperation
from io import BytesIO
from pathlib import Path


def _safe_decimal(value: str) -> Decimal | None:
    try:
        clean = re.sub(r"[^\d.,-]", "", str(value)).replace(",", ".")
        return Decimal(clean)
    except InvalidOperation:
        return None


def excel_to_text(content: bytes, filename: str) -> str:
    """Конвертирует Excel/CSV выписку в текст для LLM."""
    import pandas as pd

    ext = Path(filename).suffix.lower()

    if ext in {".xls", ".xlsx"}:
        df = pd.read_excel(BytesIO(content), dtype=str)
    elif ext == ".csv":
        for enc in ("utf-8", "windows-1251", "utf-8-sig"):
            try:
                df = pd.read_csv(BytesIO(content), encoding=enc, sep=None, engine="python", dtype=str)
                break
            except Exception:
                continue
        else:
            return "Не удалось прочитать CSV файл."
    else:
        return f"Формат {ext} не поддерживается этим конвертером."

    df.columns = [str(c).strip() for c in df.columns]
    df = df.dropna(how="all")

    lines = [f"Выписка из файла: {filename}"]
    lines.append(f"Строк данных: {len(df)}")
    lines.append(f"Колонки: {', '.join(df.columns.tolist())}")
    lines.append("")

    # Попытка стандартного представления (первые 100 строк)
    preview_rows = df.head(100)
    lines.append("=== Данные (первые 100 строк) ===")
    for _, row in preview_rows.iterrows():
        row_str = " | ".join(f"{col}: {val}" for col, val in row.items() if pd.notna(val) and str(val).strip())
        if row_str:
            lines.append(row_str)

    if len(df) > 100:
        lines.append(f"... и ещё {len(df) - 100} строк")

    return "\n".join(lines)


def pdf_to_text(content: bytes, filename: str, max_pages: int = 10) -> str:
    """Извлекает текст из PDF выписки."""
    try:
        import pdfplumber
        lines = [f"PDF выписка: {filename}"]
        with pdfplumber.open(BytesIO(content)) as pdf:
            total = len(pdf.pages)
            lines.append(f"Страниц: {total} (обрабатываем первые {min(max_pages, total)})")
            lines.append("")
            for i, page in enumerate(pdf.pages[:max_pages]):
                text = page.extract_text() or ""
                if text.strip():
                    lines.append(f"--- Страница {i+1} ---")
                    lines.append(text.strip())
        return "\n".join(lines)
    except Exception as e:
        return f"Ошибка чтения PDF: {e}"


def transactions_to_analysis_text(transactions: list[dict]) -> str:
    """
    Превращает список транзакций в компактный текст для финансового анализа.
    Группирует по мерчанту, считает итоги.
    """
    if not transactions:
        return "Транзакций нет."

    total_income = sum(float(t.get("amount", 0)) for t in transactions if t.get("is_income"))
    total_expense = sum(float(t.get("amount", 0)) for t in transactions if not t.get("is_income"))

    # Группировка по мерчанту
    merchants: dict[str, dict] = {}
    for t in transactions:
        merchant = str(t.get("merchant_name", "Неизвестно"))[:60]
        if merchant not in merchants:
            merchants[merchant] = {"total": 0.0, "count": 0, "is_income": t.get("is_income", False)}
        merchants[merchant]["total"] += float(t.get("amount", 0))
        merchants[merchant]["count"] += 1

    # Топ-20 расходов и топ-5 доходов
    expenses = sorted(
        [(m, d) for m, d in merchants.items() if not d["is_income"]],
        key=lambda x: x[1]["total"], reverse=True
    )[:20]
    incomes = sorted(
        [(m, d) for m, d in merchants.items() if d["is_income"]],
        key=lambda x: x[1]["total"], reverse=True
    )[:5]

    lines = [
        f"Финансовые данные пользователя:",
        f"Всего транзакций: {len(transactions)}",
        f"Суммарный доход: {total_income:,.0f} ₽",
        f"Суммарный расход: {total_expense:,.0f} ₽",
        f"Баланс: {total_income - total_expense:,.0f} ₽",
        "",
        "Топ расходы (мерчант — сумма — кол-во операций):",
    ]
    for merchant, data in expenses:
        lines.append(f"  {merchant}: {data['total']:,.0f} ₽ ({data['count']} раз)")

    if incomes:
        lines.append("\nИсточники дохода:")
        for merchant, data in incomes:
            lines.append(f"  {merchant}: {data['total']:,.0f} ₽ ({data['count']} раз)")

    return "\n".join(lines)


def file_to_text(content: bytes, filename: str) -> str:
    """Главная точка входа. Определяет тип и конвертирует."""
    ext = Path(filename).suffix.lower()
    if ext == ".pdf":
        return pdf_to_text(content, filename)
    return excel_to_text(content, filename)
