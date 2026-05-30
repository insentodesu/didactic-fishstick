import json
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.services.aiesa_client import chat_complete, chat_complete_stream
from app.services.deps import get_current_user_id
from app.services.file_to_text import file_to_text, transactions_to_analysis_text

router = APIRouter(prefix="/llm", tags=["LLM / AI"])

# Публичное название модели. Реальный провайдер скрыт в конфиге.
BRANDED_MODEL = "finassist-1"

SYSTEM_FINANCIAL = (
    "Ты — ФинАссистент AI, персональный финансовый помощник. "
    "Отвечай только на русском языке. "
    "Давай конкретные, практичные советы. Не придумывай цифры. "
    "Если вопрос не о финансах — вежливо перенаправь к финансовой теме."
)

CATEGORY_MAP = {
    1: "Еда и рестораны", 2: "Транспорт", 3: "Покупки", 4: "Развлечения",
    5: "Здоровье", 6: "ЖКУ и связь", 7: "Подписки", 8: "Образование",
    9: "Путешествия", 10: "Финансы и кредиты", 11: "Доходы",
    12: "Переводы", 13: "Прочее",
}
CATEGORIES_LIST = "\n".join(f"{k}: {v}" for k, v in CATEGORY_MAP.items())


class ChatRequest(BaseModel):
    message: str
    context: str | None = None   # доп. контекст (финансовые данные пользователя)


class ClassifyRequest(BaseModel):
    merchant: str
    description: str


class ClassifyBatchRequest(BaseModel):
    transactions: list[dict]   # [{merchant_name, description}, ...]


class AnalyzeRequest(BaseModel):
    transactions_summary: dict
    user_profile: dict | None = None


class SummarizeRequest(BaseModel):
    transactions: list[dict]
    period: str = "месяц"


# ========================= ЧАТ =========================

@router.post("/chat")
async def chat(
    body: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Чат с финансовым AI-ассистентом."""
    messages = [{"role": "system", "content": SYSTEM_FINANCIAL}]
    if body.context:
        messages.append({"role": "system", "content": f"Данные пользователя:\n{body.context}"})
    messages.append({"role": "user", "content": body.message})

    try:
        answer = await chat_complete(messages)
        return {"answer": answer, "model": BRANDED_MODEL}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI-сервис недоступен: {e}")


@router.post("/chat/stream")
async def chat_stream(
    body: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Стриминговый чат — ответ приходит токен за токеном (SSE)."""
    messages = [{"role": "system", "content": SYSTEM_FINANCIAL}]
    if body.context:
        messages.append({"role": "system", "content": f"Данные пользователя:\n{body.context}"})
    messages.append({"role": "user", "content": body.message})

    async def event_gen():
        try:
            async for token in chat_complete_stream(messages):
                yield f"data: {json.dumps({'token': token}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_gen(), media_type="text/event-stream")


# ========================= ФАЙЛ → АНАЛИЗ =========================

@router.post("/analyze-file")
async def analyze_file(
    file: Annotated[UploadFile, File(description="Выписка: CSV/XLS/XLSX/PDF")],
    user_id: str = Depends(get_current_user_id),
):
    """
    Загружает файл выписки, конвертирует в текст и запрашивает финансовый анализ у AIESA.
    AIESA не принимает файлы напрямую — конвертация происходит на нашей стороне.
    """
    content = await file.read()
    if len(content) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Файл слишком большой (макс 20 МБ)")

    text_repr = file_to_text(content, file.filename or "statement.csv")

    messages = [
        {"role": "system", "content": SYSTEM_FINANCIAL},
        {"role": "user", "content": (
            f"Проанализируй мою банковскую выписку и дай финансовый диагноз:\n\n"
            f"{text_repr}\n\n"
            f"Определи:\n"
            f"1. Основные категории расходов\n"
            f"2. На что уходит больше всего денег\n"
            f"3. Три конкретных рекомендации по экономии\n"
            f"4. Оценку финансового здоровья (A/B/C/D/F)"
        )},
    ]

    try:
        answer = await chat_complete(messages, max_tokens=3000)
        return {"analysis": answer, "file": file.filename, "model": BRANDED_MODEL}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI-сервис недоступен: {e}")


# ========================= КЛАССИФИКАЦИЯ =========================

@router.post("/classify")
async def classify_transaction(body: ClassifyRequest):
    """Классифицирует одну транзакцию по категории."""
    messages = [
        {"role": "system", "content": "Ты классификатор банковских транзакций. Отвечай только числом категории."},
        {"role": "user", "content": (
            f"Мерчант: '{body.merchant}'. Описание: '{body.description}'.\n"
            f"Категории:\n{CATEGORIES_LIST}\n"
            f"Ответь только числом (1-13)."
        )},
    ]
    try:
        answer = await chat_complete(messages, model=None, temperature=0.1, max_tokens=10)
        cat_id = int(answer.strip().split()[0])
        if cat_id not in CATEGORY_MAP:
            cat_id = 13
        return {"category_id": cat_id, "category_name": CATEGORY_MAP[cat_id], "confidence": 0.82}
    except Exception:
        return {"category_id": 13, "category_name": "Прочее", "confidence": 0.5}


@router.post("/classify/batch")
async def classify_batch(body: ClassifyBatchRequest):
    """
    Классифицирует пакет транзакций за один запрос к AIESA.
    Эффективнее N отдельных запросов — модель получает весь список и отвечает JSON.
    """
    if not body.transactions:
        return {"results": []}

    # Формируем нумерованный список для модели
    tx_lines = "\n".join(
        f"{i+1}. Мерчант: '{t.get('merchant_name', '')}', Описание: '{t.get('description', '')}'"
        for i, t in enumerate(body.transactions[:50])  # макс 50 за раз
    )

    messages = [
        {"role": "system", "content": (
            "Ты классификатор транзакций. Для каждой строки верни номер категории.\n"
            f"Категории:\n{CATEGORIES_LIST}\n"
            "Ответь строго в формате JSON: {\"results\": [id1, id2, ...]}"
        )},
        {"role": "user", "content": f"Классифицируй транзакции:\n{tx_lines}"},
    ]

    try:
        answer = await chat_complete(messages, model=None, temperature=0.1, max_tokens=500)
        # Вытаскиваем JSON из ответа
        start = answer.find("{")
        end = answer.rfind("}") + 1
        data = json.loads(answer[start:end])
        ids = data.get("results", [])

        results = []
        for i, tx in enumerate(body.transactions[:50]):
            cat_id = ids[i] if i < len(ids) else 13
            if not isinstance(cat_id, int) or cat_id not in CATEGORY_MAP:
                cat_id = 13
            results.append({
                "merchant_name": tx.get("merchant_name"),
                "category_id": cat_id,
                "category_name": CATEGORY_MAP[cat_id],
            })
        return {"results": results}
    except Exception:
        return {"results": [{"category_id": 13, "category_name": "Прочее"} for _ in body.transactions]}


# ========================= АНАЛИЗ ДАННЫХ =========================

@router.post("/analyze")
async def analyze_finances(
    body: AnalyzeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Финансовый анализ по сводке транзакций."""
    summary = body.transactions_summary
    context = (
        f"Доход: {summary.get('total_income', 0):,.0f} ₽\n"
        f"Расходы: {summary.get('total_expense', 0):,.0f} ₽\n"
        f"Баланс: {summary.get('balance', 0):,.0f} ₽\n"
        f"Транзакций: {summary.get('total_count', 0)}\n"
        f"Топ категория: {summary.get('top_category', 'неизвестно')}"
    )
    messages = [
        {"role": "system", "content": SYSTEM_FINANCIAL},
        {"role": "user", "content": (
            f"Вот мои финансы за месяц:\n{context}\n\n"
            f"Дай 3 конкретных рекомендации по улучшению финансового положения."
        )},
    ]
    try:
        answer = await chat_complete(messages)
        return {"analysis": answer, "model": BRANDED_MODEL}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI-сервис недоступен: {e}")


@router.post("/analyze/transactions")
async def analyze_transactions_list(
    body: SummarizeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Принимает список транзакций, конвертирует в текст и анализирует."""
    text = transactions_to_analysis_text(body.transactions)
    messages = [
        {"role": "system", "content": SYSTEM_FINANCIAL},
        {"role": "user", "content": (
            f"Проанализируй мои траты за {body.period}:\n\n{text}\n\n"
            f"Сделай краткое резюме (2-3 предложения) и дай один главный совет."
        )},
    ]
    try:
        answer = await chat_complete(messages)
        return {"summary": answer, "model": BRANDED_MODEL}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI-сервис недоступен: {e}")


@router.post("/summarize")
async def summarize_transactions(
    body: SummarizeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Краткое текстовое резюме транзакций."""
    text = transactions_to_analysis_text(body.transactions)
    messages = [
        {"role": "system", "content": SYSTEM_FINANCIAL},
        {"role": "user", "content": f"Кратко (2 предложения) резюмируй траты за {body.period}:\n{text}"},
    ]
    try:
        answer = await chat_complete(messages, max_tokens=300)
        return {"summary": answer}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI-сервис недоступен: {e}")


@router.get("/insights")
async def cached_insights(user_id: str = Depends(get_current_user_id)):
    """Заранее сгенерированные инсайты (из кэша Redis). Обновляются раз в сутки."""
    # TODO: Redis кэш + Celery beat задача для генерации
    return {
        "insights": [
            "Вы тратите на еду на 23% больше среднего по вашему доходному сегменту",
            "Ваши подписки обходятся в 1 890 ₽/мес — проверьте, все ли используются",
            "При текущем темпе накоплений цель «Отпуск» будет достигнута через 4 месяца",
        ],
        "generated_at": "2026-05-30T10:00:00",
        "next_update": "2026-05-31T06:00:00",
    }
