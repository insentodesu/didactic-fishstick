"""
Аналитический сервис.
Агрегирует данные из transaction-service, считает ПДН, прогноз, онбординг.
"""

from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
import httpx

from app.config import settings
from app.services.deps import get_current_user_id
from app.services.health_score import calculate_health_score, calculate_credit_traffic_light

router = APIRouter(prefix="/analytics", tags=["Аналитика"])

# ─── demo data ───────────────────────────────────────────────────────────────

_DEMO = {
    "user": "Алексей М.",
    "monthly_income": 92000.0,
    "monthly_debt_payment": 43264.0,
    "monthly_expenses": 28600.0,
    "pdn": 47.0,
    "zone": "yellow",
    "health_score": 51,
    "free_amount": 20136.0,
    "streak": 12,
    "pet": {"name": "Бади", "level": 3, "hunger": 60, "happiness": 80},
}

_MONTH_LABELS_RU = ["Янв", "Фев", "Мар", "Апр", "Май", "Июн", "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек"]

def _month_label(d: date) -> str:
    return _MONTH_LABELS_RU[d.month - 1]


# ─── helpers ─────────────────────────────────────────────────────────────────

def _plan_steps(pdn: float, monthly_income: float, monthly_debt: float) -> list[dict]:
    steps = []
    if monthly_debt > 0:
        steps.append({"title": "Объединить дорогие кредиты в один", "done": False, "now": False})
    if pdn > 50:
        steps.append({"title": f"Закрыть самый дорогой кредит", "done": False, "now": True})
        steps.append({"title": "Снизить кредитный лимит карты", "done": False})
    elif pdn > 30:
        steps.append({"title": "Досрочно погасить часть долга", "done": False, "now": True})
        steps.append({"title": "Снизить кредитный лимит карты", "done": False})
    steps.append({"title": "Рефинансировать крупный кредит", "done": False})
    steps.append({"title": f"Выйти в зелёную зону · ПДН 30%", "done": False})
    return steps


async def _fetch_tx_stats(user_id: str, token: str, date_from: date | None = None, date_to: date | None = None) -> dict:
    params = {"page_size": 1000}
    if date_from:
        params["date_from"] = str(date_from)
    if date_to:
        params["date_to"] = str(date_to)
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(
            f"{settings.transaction_service_url}/transactions/stats",
            params=params,
            headers={"Authorization": f"Bearer {token}"},
        )
        resp.raise_for_status()
    return resp.json()


def _extract_token(request: Request) -> str:
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]
    return ""


# ─── endpoints ───────────────────────────────────────────────────────────────

@router.get("/traffic-light")
async def traffic_light(
    request: Request,
    demo: bool = Query(False),
    user_id: str = Depends(get_current_user_id),
):
    """Кредитный светофор: ПДН, зона, план шагов."""
    if demo:
        d = _DEMO
        income = d["monthly_income"]
        debt = d["monthly_debt_payment"]
        zone = d["zone"]
        pdn = d["pdn"]
        advice_map = {
            "green": "Долговая нагрузка в норме. Отличная работа!",
            "yellow": f"{pdn:.0f}% дохода уходит на кредиты. Давай снизим до 30%.",
            "red": f"Высокая нагрузка — ПДН {pdn:.0f}%. Нужен план сейчас.",
        }
        return {
            "pdn": pdn, "zone": zone,
            "advice": advice_map[zone],
            "monthly_income": income,
            "monthly_debt": debt,
            "plan_steps": [
                {"title": "Объединить 2 дорогих кредита", "done": True, "now": False},
                {"title": "Закрыть микрозайм 18 900 ₽", "done": True, "now": False},
                {"title": "Снизить лимит по карте", "done": True, "now": False},
                {"title": "Досрочно погасить 30 000 ₽", "done": False, "now": True},
                {"title": "Рефинансировать ипотеку", "done": False, "now": False},
                {"title": "Выйти в зелёную зону · ПДН 30%", "done": False, "now": False},
            ],
        }

    token = _extract_token(request)
    today = date.today()
    month_start = today.replace(day=1)

    try:
        stats = await _fetch_tx_stats(user_id, token, month_start, today)
    except Exception:
        raise HTTPException(status_code=503, detail="Не удалось получить данные транзакций")

    income = float(stats.get("total_income", 0))
    expense = float(stats.get("total_expense", 0))
    # debt = category 'finance' (id=10) — используем 30% expenses как proxy если нет разбивки
    debt = 0.0

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            cr = await client.get(
                f"{settings.transaction_service_url}/transactions/categories",
                params={"date_from": str(month_start), "date_to": str(today), "page_size": 100},
                headers={"Authorization": f"Bearer {token}"},
            )
            for cat in (cr.json() if cr.is_success else []):
                if (cat.get("name_ru") or "").lower() in ("финансы и кредиты", "кредиты", "finance"):
                    debt += float(cat.get("total", 0))
    except Exception:
        pass

    zone, pdn, advice = calculate_credit_traffic_light(income, debt)
    steps = _plan_steps(pdn, income, debt)

    return {
        "pdn": pdn, "zone": zone, "advice": advice,
        "monthly_income": income, "monthly_debt": debt,
        "plan_steps": steps,
    }


@router.get("/forecast")
async def forecast(
    request: Request,
    demo: bool = Query(False),
    months: int = Query(6, ge=1, le=12),
    user_id: str = Depends(get_current_user_id),
):
    """Помесячная динамика ПДН + прогноз + картина текущего месяца."""
    if demo:
        d = _DEMO
        return {
            "current": {
                "income": d["monthly_income"],
                "debt_payment": d["monthly_debt_payment"],
                "expenses": d["monthly_expenses"],
                "free": d["free_amount"],
                "pdn": d["pdn"],
            },
            "history": [
                {"month": "2026-01", "month_label": "Янв", "income": 88000, "debt_payment": 45000, "pdn": 51.1},
                {"month": "2026-02", "month_label": "Фев", "income": 88000, "debt_payment": 43000, "pdn": 48.9},
                {"month": "2026-03", "month_label": "Мар", "income": 90000, "debt_payment": 44000, "pdn": 48.9},
                {"month": "2026-04", "month_label": "Апр", "income": 90000, "debt_payment": 44000, "pdn": 48.9},
                {"month": "2026-05", "month_label": "Май", "income": 92000, "debt_payment": 43264, "pdn": 47.0},
            ],
            "forecast": [
                {"month": "2026-06", "month_label": "Июн", "pdn": 43.0, "projected": True},
                {"month": "2026-07", "month_label": "Июл", "pdn": 39.0, "projected": True},
            ],
            "fixed_expenses": [
                {"emoji": "🏠", "name": "ЖКУ", "period": "ежемесячно", "amount": 4800},
                {"emoji": "📱", "name": "МТС", "period": "ежемесячно", "amount": 650},
                {"emoji": "🎬", "name": "Кинопоиск", "period": "ежемесячно", "amount": 399},
                {"emoji": "🎵", "name": "Яндекс Плюс", "period": "ежемесячно", "amount": 299},
            ],
        }

    token = _extract_token(request)
    today = date.today()

    history = []
    for i in range(months - 2, -1, -1):
        mo_start = (today.replace(day=1) - timedelta(days=i * 30)).replace(day=1)
        last_day = (mo_start.replace(month=mo_start.month % 12 + 1, day=1) - timedelta(days=1))
        try:
            stats = await _fetch_tx_stats(user_id, token, mo_start, min(last_day, today))
            inc = float(stats.get("total_income", 0))
            pdn = 0.0
            history.append({
                "month": mo_start.strftime("%Y-%m"),
                "month_label": _month_label(mo_start),
                "income": inc,
                "debt_payment": 0.0,
                "pdn": pdn,
            })
        except Exception:
            pass

    # Прогноз — линейная экстраполяция
    forecast_list = []
    if len(history) >= 2:
        last_pdn = history[-1]["pdn"]
        prev_pdn = history[-2]["pdn"]
        trend = (last_pdn - prev_pdn) if len(history) >= 2 else 0
        for j in range(1, 3):
            proj_date = today.replace(day=1)
            for _ in range(j):
                proj_date = (proj_date.replace(day=28) + timedelta(days=4)).replace(day=1)
            proj_pdn = max(0, last_pdn + trend * j * 0.8)
            forecast_list.append({
                "month": proj_date.strftime("%Y-%m"),
                "month_label": _month_label(proj_date),
                "pdn": round(proj_pdn, 1),
                "projected": True,
            })

    # Текущий месяц
    month_start = today.replace(day=1)
    try:
        cur = await _fetch_tx_stats(user_id, token, month_start, today)
        income = float(cur.get("total_income", 0))
        expenses = float(cur.get("total_expense", 0))
    except Exception:
        income, expenses = 0.0, 0.0

    debt = 0.0
    free = income - debt - expenses

    return {
        "current": {
            "income": income, "debt_payment": debt,
            "expenses": expenses, "free": free,
            "pdn": debt / max(income, 1) * 100,
        },
        "history": history,
        "forecast": forecast_list,
        "fixed_expenses": [],
    }


class OnboardingRequest(BaseModel):
    monthly_income: float
    has_credits: bool
    monthly_debt_payment: float = 0.0
    goals: list[str] = []
    barriers: list[str] = []
    statement_id: str | None = None


@router.post("/onboarding")
async def onboarding(
    body: OnboardingRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Принимает данные онбординга, считает ПДН, строит AI-план."""
    income = body.monthly_income
    debt = body.monthly_debt_payment if body.has_credits else 0.0
    expenses = income * 0.3  # proxy

    zone_str, pdn, advice = calculate_credit_traffic_light(income, debt)
    score, breakdown = calculate_health_score(income, expenses, debt, 0, 0)
    steps = _plan_steps(pdn, income, debt)

    # AI message via LLM service
    ai_message = (
        f"Ты в {'зелёной' if zone_str == 'green' else 'жёлтой' if zone_str == 'yellow' else 'красной'} зоне. "
        f"ПДН {pdn:.0f}% — {advice} "
        f"Первый шаг: {steps[0]['title'] if steps else 'загрузи выписку из банка'}."
    )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{settings.llm_service_url}/llm/chat",
                json={
                    "message": (
                        f"Пользователь: доход {income:.0f}₽, платёж по кредитам {debt:.0f}₽, ПДН {pdn:.0f}%, зона {zone_str}. "
                        f"Цели: {', '.join(body.goals)}. Барьеры: {', '.join(body.barriers)}. "
                        f"Напиши тёплое, конкретное сообщение (2–3 предложения) с конкретным первым шагом. "
                        f"Язык: русский, на «ты», без осуждения."
                    )
                },
                headers={"Authorization": "Bearer internal"},
            )
            if resp.is_success:
                ai_message = resp.json().get("answer", ai_message)
    except Exception:
        pass

    return {
        "pdn": pdn,
        "zone": zone_str,
        "health_score": score,
        "plan_steps": steps,
        "ai_message": ai_message,
        "breakdown": breakdown,
    }


# ─── existing endpoints (refactored) ─────────────────────────────────────────

@router.get("/dashboard")
async def dashboard(
    request: Request,
    demo: bool = Query(False),
    user_id: str = Depends(get_current_user_id),
):
    """Главный дашборд."""
    if demo:
        d = _DEMO
        return {
            "period": {"from": date.today().replace(day=1).isoformat(), "to": date.today().isoformat()},
            "health_score": d["health_score"],
            "total_income": d["monthly_income"],
            "total_expense": d["monthly_expenses"] + d["monthly_debt_payment"],
            "savings_rate": round((d["free_amount"] / d["monthly_income"]) * 100, 1),
            "top_category": "Обслуживание долга",
            "pdn": d["pdn"],
            "zone": d["zone"],
            "alerts": [
                {"type": "subscription", "message": "3 подписки списаны вчера на 890 ₽"},
                {"type": "pdn", "message": f"ПДН {d['pdn']:.0f}% — жёлтая зона. Давай снизим до 30%."},
            ],
        }

    token = _extract_token(request)
    today = date.today()
    month_start = today.replace(day=1)

    try:
        stats = await _fetch_tx_stats(user_id, token, month_start, today)
    except Exception:
        stats = {}

    income = float(stats.get("total_income", 0))
    expense = float(stats.get("total_expense", 0))
    balance = income - expense
    savings_rate = round(balance / income * 100, 1) if income > 0 else 0.0

    return {
        "period": {"from": month_start.isoformat(), "to": today.isoformat()},
        "health_score": 0,
        "total_income": income,
        "total_expense": expense,
        "savings_rate": savings_rate,
        "top_category": "—",
        "alerts": [],
    }


@router.get("/financial-health")
async def financial_health(
    monthly_income: float = Query(...),
    monthly_expense: float = Query(...),
    monthly_debt_payment: float = Query(0),
    total_debt: float = Query(0),
    savings: float = Query(0),
    user_id: str = Depends(get_current_user_id),
):
    score, breakdown = calculate_health_score(monthly_income, monthly_expense, monthly_debt_payment, total_debt, savings)
    return {"score": score, "breakdown": breakdown, "grade": _score_to_grade(score)}


@router.get("/credit-traffic-light")
async def credit_traffic_light(
    monthly_income: float = Query(...),
    monthly_debt_payment: float = Query(...),
    user_id: str = Depends(get_current_user_id),
):
    color, pdn, advice = calculate_credit_traffic_light(monthly_income, monthly_debt_payment)
    return {"color": color, "pdn_percent": pdn, "cb_norm_percent": 50, "advice": advice}


@router.get("/diagnosis")
async def financial_diagnosis(
    monthly_income: float = Query(...),
    monthly_expense: float = Query(...),
    monthly_debt_payment: float = Query(0),
    savings: float = Query(0),
    user_id: str = Depends(get_current_user_id),
):
    score, breakdown = calculate_health_score(monthly_income, monthly_expense, monthly_debt_payment, 0, savings)
    action = _pick_weekly_action(breakdown)
    return {
        "score": score, "grade": _score_to_grade(score), "breakdown": breakdown,
        "weekly_action": action,
        "summary": f"Твой финансовый балл: {score}/100. {action['title']}",
    }


@router.post("/chat")
async def ai_chat(
    request: Request,
    message: str,
    user_id: str = Depends(get_current_user_id),
):
    token = _extract_token(request)
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                f"{settings.llm_service_url}/llm/chat",
                json={"message": message},
                headers={"Authorization": f"Bearer {token}"},
            )
            resp.raise_for_status()
        return resp.json()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"AI недоступен: {e}")


@router.get("/recommendations")
async def get_recommendations(user_id: str = Depends(get_current_user_id)):
    return {
        "recommendations": [
            {"id": 1, "title": "Откройте накопительный счёт", "description": "При регулярном остатке ~15 000 ₽ накопительный счёт под 16% принесёт 2 400 ₽/год.", "type": "investment", "priority": "high", "potential_gain_rub": 2400},
            {"id": 2, "title": "Проверьте подписки", "description": "Найдено несколько регулярных списаний. Проверьте, все ли активно используются.", "type": "subscription", "priority": "medium", "potential_gain_rub": 890},
        ]
    }


@router.get("/spending-patterns")
async def spending_patterns(user_id: str = Depends(get_current_user_id), months: int = Query(3)):
    return {
        "weekly_pattern": {"Mon": 1200, "Tue": 800, "Wed": 950, "Thu": 1100, "Fri": 2400, "Sat": 3200, "Sun": 1800},
        "peak_day": "Суббота", "peak_category": "Рестораны и доставка",
        "monthly_trend": "снижение расходов на 8% по сравнению с прошлым месяцем",
    }


@router.get("/anomalies")
async def detect_anomalies(user_id: str = Depends(get_current_user_id), sensitivity: float = Query(2.0)):
    return {"anomalies": [], "total_found": 0}


@router.post("/recommendations/{recommendation_id}/apply")
async def apply_recommendation(recommendation_id: int, user_id: str = Depends(get_current_user_id)):
    return {"status": "applied", "recommendation_id": recommendation_id}


def _score_to_grade(score: int) -> str:
    if score >= 80: return "A"
    if score >= 65: return "B"
    if score >= 50: return "C"
    if score >= 35: return "D"
    return "F"


def _pick_weekly_action(breakdown: dict) -> dict:
    weakest = min(breakdown, key=lambda k: breakdown[k]["score"])
    return {
        "savings_rate": {"title": "Открой накопительный счёт и переведи 5% дохода", "url": "/investments/deposits"},
        "debt_load": {"title": "Составь план досрочного погашения самого дорогого кредита", "url": "/analytics/credit-traffic-light"},
        "expense_control": {"title": "Установи лимит на категорию «Рестораны» на эту неделю", "url": "/transactions/categories"},
    }.get(weakest, {"title": "Добавь выписку за последний месяц для анализа", "url": "/transactions/upload"})
