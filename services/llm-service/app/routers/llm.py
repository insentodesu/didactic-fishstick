from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.services.deps import get_current_user_id
from app.services.rag_pipeline import ask

router = APIRouter(prefix="/llm", tags=["LLM / AI"])

CATEGORY_MAP = {
    1: "Еда и рестораны",
    2: "Транспорт",
    3: "Покупки",
    4: "Развлечения",
    5: "Здоровье",
    6: "ЖКУ и связь",
    7: "Подписки",
    8: "Образование",
    9: "Путешествия",
    10: "Финансы и кредиты",
    11: "Доходы",
    12: "Переводы",
    13: "Прочее",
}


class ChatRequest(BaseModel):
    message: str
    user_id: str | None = None
    context: dict | None = None   # дополнительный финансовый контекст


class ClassifyRequest(BaseModel):
    merchant: str
    description: str


class AnalyzeRequest(BaseModel):
    transactions_summary: dict
    user_profile: dict | None = None


class SummarizeRequest(BaseModel):
    transactions: list[dict]
    period: str = "месяц"


@router.post("/chat")
async def chat(
    body: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Чат с финансовым AI-ассистентом через RAG."""
    try:
        answer = await ask(body.message)
        return {"answer": answer, "model": "llama3.1:8b", "method": "rag"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"LLM недоступен: {str(e)}")


@router.post("/classify")
async def classify_transaction(body: ClassifyRequest):
    """
    Классифицирует транзакцию по категории через LLM.
    Используется когда словарный матчинг не дал уверенного результата.
    """
    categories_list = "\n".join(f"{k}: {v}" for k, v in CATEGORY_MAP.items())
    prompt = (
        f"Определи категорию транзакции. Мерчант: '{body.merchant}'. "
        f"Описание: '{body.description}'.\n"
        f"Категории:\n{categories_list}\n"
        f"Ответь только числом категории (1-13)."
    )
    try:
        answer = await ask(prompt)
        cat_id = int(answer.strip().split()[0])
        if cat_id not in CATEGORY_MAP:
            cat_id = 13
        return {"category_id": cat_id, "category_name": CATEGORY_MAP[cat_id], "confidence": 0.75}
    except Exception:
        return {"category_id": 13, "category_name": "Прочее", "confidence": 0.5}


@router.post("/analyze")
async def analyze_finances(
    body: AnalyzeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Глубокий AI-анализ финансового состояния пользователя."""
    summary = body.transactions_summary
    prompt = (
        f"Проанализируй финансы пользователя за месяц:\n"
        f"Доход: {summary.get('total_income', 0)} ₽\n"
        f"Расходы: {summary.get('total_expense', 0)} ₽\n"
        f"Топ категория трат: {summary.get('top_category', 'неизвестно')}\n"
        f"Дай 3 конкретных рекомендации по улучшению финансового положения."
    )
    try:
        answer = await ask(prompt)
        return {"analysis": answer, "model": "llama3.1:8b"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"LLM недоступен: {str(e)}")


@router.post("/summarize")
async def summarize_transactions(
    body: SummarizeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Краткое текстовое резюме транзакций за период."""
    top_merchants = body.transactions[:5]
    prompt = (
        f"Сделай краткое резюме трат за {body.period} в 2-3 предложениях. "
        f"Топ транзакции: {top_merchants}. "
        f"Укажи главный паттерн и один совет."
    )
    try:
        answer = await ask(prompt)
        return {"summary": answer}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"LLM недоступен: {str(e)}")


@router.get("/insights")
async def cached_insights(user_id: str = Depends(get_current_user_id)):
    """Заранее сгенерированные инсайты (из кэша Redis). Обновляются раз в сутки."""
    # TODO: интеграция с Redis кэшем
    return {
        "insights": [
            "Вы тратите на еду на 23% больше среднего по вашему доходному сегменту",
            "Ваши подписки обходятся в 1 890 ₽/мес — проверьте, все ли активно используются",
            "При текущем темпе накоплений цель «Отпуск» будет достигнута через 4 месяца",
        ],
        "generated_at": "2026-05-30T10:00:00",
        "next_update": "2026-05-31T06:00:00",
    }
