"""Извлечение текста из PDF/Excel/CSV для передачи в LLM."""

from io import BytesIO
from pathlib import Path


def excel_to_text(content: bytes, filename: str) -> str:
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
        return f"Формат {ext} не поддерживается."

    df.columns = [str(c).strip() for c in df.columns]
    df = df.dropna(how="all")

    lines = [f"Выписка из файла: {filename}", f"Строк данных: {len(df)}"]
    lines.append(f"Колонки: {', '.join(df.columns.tolist())}")
    lines.append("")
    lines.append("=== Данные (первые 150 строк) ===")
    for _, row in df.head(150).iterrows():
        row_str = " | ".join(
            f"{col}: {val}" for col, val in row.items() if pd.notna(val) and str(val).strip()
        )
        if row_str:
            lines.append(row_str)
    if len(df) > 150:
        lines.append(f"... и ещё {len(df) - 150} строк")
    return "\n".join(lines)


def pdf_to_text(content: bytes, filename: str, max_pages: int = 15) -> str:
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
                    lines.append(f"--- Страница {i + 1} ---")
                    lines.append(text.strip())
        return "\n".join(lines)
    except Exception as e:
        return f"Ошибка чтения PDF: {e}"


def file_to_text(content: bytes, filename: str) -> str:
    ext = Path(filename).suffix.lower()
    if ext == ".pdf":
        return pdf_to_text(content, filename)
    return excel_to_text(content, filename)
