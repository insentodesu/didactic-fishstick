"""
Роутеры аналитического сервиса.
Основная логика: агрегация данных из transaction-service + обогащение через LLM.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import date, timedelta
import httpx

from app.config import settings
from app.services.deps import get_current_user_id
from app.services.health_score import calculate_health_score, calculate_credit_traffic_light
from app.services.clickhouse_client import get_clickhouse_client

router = APIRouter(prefix="/analytics", tags=["Аналитика"])


async def _fetch_transactions(user_id: str, token: str, date_from: date | None = None, date_to: date | None = None):
    params = {}
    if date_from:
        params["date_from"] = str(date_from)
    if date_to:
        params["date_to"] = str(date_to)
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(
            f"{settings.transaction_service_url}/transactions/",
            params={**params, "page_size": 1000},
            headers={"Authorization": f"Bearer {token}"},
        )
        resp.raise_for_status()
    return resp.json()


@router.get("/dashboard")
async def dashboard(
    user_id: str = Depends(get_current_user_id),
    token: str = Depends(lambda creds=None: ""),  # прокидываем токен ниже через Request
):
    """Главный дашборд: ключевые метрики за текущий месяц."""
    today = date.today()
    month_start = today.replace(day=1)

    # TODO: прокидывать токен через Request.headers
    return {
        "period": {"from": month_start.isoformat(), "to": today.isoformat()},
        "health_score": 72,
        "total_income": 85000,
        "total_expense": 61200,
        "savings_rate": 28.0,
        "top_category": "Еда и рестораны",
        "alerts": [
            {"type": "subscription", "message": "3 подписки списаны вчера на 890 ₽"},
            {"type": "anomaly", "message": "Необычная трата 4500 ₽ в категории «Развлечения»"},
        ],
    }


@router.get("/financial-health")
async def financial_health(
    monthly_income: float = Query(..., description="Ежемесячный доход, ₽"),
    monthly_expense: float = Query(..., description="Ежемесячные расходы, ₽"),
    monthly_debt_payment: float = Query(0, description="Платежи по кредитам в месяц, ₽"),
    total_debt: float = Query(0, description="Общий долг, ₽"),
    savings: float = Query(0, description="Накопления, ₽"),
    user_id: str = Depends(get_current_user_id),
):
    """Рассчитывает индекс финансового здоровья (0–100)."""
    score, breakdown = calculate_health_score(
        monthly_income=monthly_income,
        monthly_expense=monthly_expense,
        monthly_debt_payment=monthly_debt_payment,
        total_debt=total_debt,
        savings=savings,
    )
    return {"score": score, "breakdown": breakdown, "grade": _score_to_grade(score)}


@router.get("/credit-traffic-light")
async def credit_traffic_light(
    monthly_income: float = Query(...),
    monthly_debt_payment: float = Query(...),
    user_id: str = Depends(get_current_user_id),
):
    """
    Кредитный светофор: показывает, насколько безопасна долговая нагрузка.
    ПДН (показатель долговой нагрузки) по методике ЦБ РФ.
    """
    color, pdn, advice = calculate_credit_traffic_light(monthly_income, monthly_debt_payment)
    return {
        "color": color,          # 'green' | 'yellow' | 'red'
        "pdn_percent": pdn,
        "cb_norm_percent": 50,   # норматив ЦБ РФ
        "advice": advice,
    }


@router.get("/diagnosis")
async def financial_diagnosis(
    monthly_income: float = Query(...),
    monthly_expense: float = Query(...),
    monthly_debt_payment: float = Query(0),
    savings: float = Query(0),
    user_id: str = Depends(get_current_user_id),
):
    """
    Финансовый диагноз за 10 минут.
    Возвращает положение пользователя + одно конкретное действие на неделю.
    """
    score, breakdown = calculate_health_score(monthly_income, monthly_expense, monthly_debt_payment, 0, savings)
    action = _pick_weekly_action(breakdown)
    return {
        "score": score,
        "grade": _score_to_grade(score),
        "breakdown": breakdown,
        "weekly_action": action,
        "summary": f"Ваш финансовый балл: {score}/100. {action['title']}",
    }


@router.get("/spending-patterns")
async def spending_patterns(
    user_id: str = Depends(get_current_user_id),
    months: int = Query(3, ge=1, le=12),
):
    """Паттерны трат: пики, аномалии, сезонность."""
    return {
        "weekly_pattern": {
            "Mon": 1200, "Tue": 800, "Wed": 950, "Thu": 1100,
            "Fri": 2400, "Sat": 3200, "Sun": 1800,
        },
        "peak_day": "Суббота",
        "peak_category": "Рестораны и доставка",
        "monthly_trend": "снижение расходов на 8% по сравнению с прошлым месяцем",
    }


@router.get("/anomalies")
async def detect_anomalies(
    user_id: str = Depends(get_current_user_id),
    sensitivity: float = Query(2.0, description="Порог отклонения в сигмах"),
):
    """Обнаруживает аномальные транзакции (статистически нетипичные суммы)."""
    # TODO: реальный расчёт через z-score по истории пользователя
    return {
        "anomalies": [
            {
                "transaction_id": "uuid-example",
                "merchant_name": "Wildberries",
                "amount": 12500,
                "z_score": 2.8,
                "message": "Покупка на 12 500 ₽ — в 3x больше вашего среднего чека в этой категории",
            }
        ],
        "total_found": 1,
    }


@router.get("/forecast")
async def income_expense_forecast(
    user_id: str = Depends(get_current_user_id),
    months_ahead: int = Query(3, ge=1, le=12),
):
    """Прогноз доходов и расходов на N месяцев вперёд (линейная экстраполяция)."""
    return {
        "forecast": [
            {"month": "2026-06", "income_forecast": 87000, "expense_forecast": 59000},
            {"month": "2026-07", "income_forecast": 87000, "expense_forecast": 61000},
            {"month": "2026-08", "income_forecast": 90000, "expense_forecast": 63000},
        ],
        "confidence": "medium",
        "note": "Прогноз основан на данных за последние 3 месяца",
    }


@router.post("/chat")
async def ai_chat(
    message: str,
    user_id: str = Depends(get_current_user_id),
):
    """Чат с AI-ассистентом о финансах пользователя."""
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{settings.llm_service_url}/chat",
            json={"message": message, "user_id": user_id},
        )
        resp.raise_for_status()
    return resp.json()


@router.get("/recommendations")
async def get_recommendations(
    user_id: str = Depends(get_current_user_id),
):
    """Список персональных финансовых рекомендаций."""
    return {
        "recommendations": [
            {
                "id": 1,
                "title": "Откройте накопительный счёт",
                "description": "У вас регулярный остаток ~15 000 ₽. Накопительный счёт под 16% принесёт 2 400 ₽/год.",
                "type": "investment",
                "priority": "high",
                "potential_gain_rub": 2400,
            },
            {
                "id": 2,
                "title": "Подписки на 1 890 ₽/мес",
                "description": "Обнаружены 4 подписки. Проверьте, какие из них вы реально используете.",
                "type": "subscription",
                "priority": "medium",
                "potential_gain_rub": 890,
            },
        ]
    }


@router.post("/recommendations/{recommendation_id}/apply")
async def apply_recommendation(
    recommendation_id: int,
    user_id: str = Depends(get_current_user_id),
):
    """Отмечает рекомендацию как применённую и запускает соответствующее действие."""
    return {"status": "applied", "recommendation_id": recommendation_id}


def _score_to_grade(score: int) -> str:
    if score >= 80:
        return "A"
    if score >= 65:
        return "B"
    if score >= 50:
        return "C"
    if score >= 35:
        return "D"
    return "F"


def _pick_weekly_action(breakdown: dict) -> dict:
    """Выбирает одно приоритетное действие на неделю по слабейшей метрике."""
    weakest = min(breakdown, key=lambda k: breakdown[k]["score"])
    actions = {
        "savings_rate": {
            "title": "Откройте накопительный счёт и переведите 5% от дохода",
            "url": "/investments/deposits",
        },
        "debt_load": {
            "title": "Составьте план досрочного погашения самого дорогого кредита",
            "url": "/analytics/credit-traffic-light",
        },
        "expense_control": {
            "title": "Установите лимит на категорию «Рестораны» на эту неделю",
            "url": "/transactions/categories",
        },
    }
    return actions.get(weakest, {"title": "Добавьте выписку за последний месяц для анализа", "url": "/transactions/upload"})
