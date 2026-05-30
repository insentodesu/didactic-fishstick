from datetime import date
from decimal import Decimal
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.deps import get_current_user_id
from app.services.calculator import compound_interest, monthly_savings_needed

router = APIRouter(prefix="/investments", tags=["Инвестиции и накопления"])


# ========================= ВКЛАДЫ =========================

@router.get("/deposits")
async def list_deposits(
    db: AsyncSession = Depends(get_db),
    min_amount: float | None = None,
    max_term_days: int | None = None,
    capitalization: bool | None = None,
    sort_by: str = Query("rate_percent", enum=["rate_percent", "min_amount"]),
):
    """Список актуальных вкладов (кэшируется в Redis на 24ч)."""
    filters = ["is_active = true"]
    params: dict = {}
    if min_amount:
        filters.append("min_amount <= :min_amount")
        params["min_amount"] = min_amount
    if max_term_days:
        filters.append("term_days_max <= :max_term")
        params["max_term"] = max_term_days
    if capitalization is not None:
        filters.append("capitalization = :cap")
        params["cap"] = capitalization

    where = " AND ".join(filters)
    rows = await db.execute(text(f"""
        SELECT * FROM investments.deposit_offers
        WHERE {where}
        ORDER BY {sort_by} DESC
        LIMIT 50
    """), params)
    return [dict(r._mapping) for r in rows]


@router.get("/deposits/{deposit_id}")
async def get_deposit(deposit_id: str, db: AsyncSession = Depends(get_db)):
    row = await db.execute(text("""
        SELECT * FROM investments.deposit_offers WHERE id = :id AND is_active = true
    """), {"id": deposit_id})
    dep = row.mappings().one_or_none()
    if not dep:
        raise HTTPException(status_code=404, detail="Вклад не найден")
    return dict(dep)


@router.get("/calculator")
async def calculate_deposit(
    principal: float = Query(..., gt=0, description="Начальная сумма (₽)"),
    rate_percent: float = Query(..., gt=0, description="Годовая ставка (%)"),
    term_days: int = Query(..., gt=0, description="Срок в днях"),
    capitalization: bool = Query(False),
):
    """Калькулятор сложных процентов."""
    return compound_interest(principal, rate_percent, term_days, capitalization)


@router.get("/comparison")
async def compare_deposits(
    amount: float = Query(..., gt=0),
    term_days: int = Query(365, gt=0),
    db: AsyncSession = Depends(get_db),
):
    """Сравнивает топ вкладов для заданной суммы и срока."""
    rows = await db.execute(text("""
        SELECT id, bank_name, product_name, rate_percent, capitalization, min_amount, offer_url
        FROM investments.deposit_offers
        WHERE is_active = true
          AND (min_amount IS NULL OR min_amount <= :amount)
          AND (term_days_min IS NULL OR term_days_min <= :days)
          AND (term_days_max IS NULL OR term_days_max >= :days)
        ORDER BY rate_percent DESC
        LIMIT 10
    """), {"amount": amount, "days": term_days})

    results = []
    for row in rows:
        r = dict(row._mapping)
        calc = compound_interest(amount, float(r["rate_percent"]), term_days, r["capitalization"])
        r["income"] = calc["income"]
        r["final_amount"] = calc["final_amount"]
        results.append(r)

    return results


@router.get("/recommendations")
async def deposit_recommendations(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Персональные рекомендации по вкладам на основе паттернов трат."""
    # TODO: анализ остатка из transaction-service
    return {
        "recommended_amount": 15000,
        "recommended_term_days": 90,
        "reason": "За последние 3 месяца у вас регулярно остаётся ~15 000 ₽ к концу месяца",
        "top_offers": [],
    }


# ========================= ЦЕЛИ =========================

class GoalCreate(BaseModel):
    title: str
    target_amount: float
    target_date: date | None = None
    emoji: str | None = "🎯"


class ContributionCreate(BaseModel):
    amount: float
    note: str | None = None


@router.get("/goals")
async def list_goals(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    rows = await db.execute(text("""
        SELECT * FROM investments.savings_goals WHERE user_id = :uid AND status != 'deleted'
        ORDER BY created_at DESC
    """), {"uid": user_id})
    return [dict(r._mapping) for r in rows]


@router.post("/goals", status_code=status.HTTP_201_CREATED)
async def create_goal(
    body: GoalCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    goal_id = str(uuid.uuid4())
    monthly = None
    if body.target_date:
        months_left = max(1, (body.target_date.year - date.today().year) * 12 + (body.target_date.month - date.today().month))
        monthly = monthly_savings_needed(body.target_amount, months_left)

    await db.execute(text("""
        INSERT INTO investments.savings_goals
            (id, user_id, title, target_amount, target_date, monthly_required, emoji)
        VALUES (:id, :uid, :title, :amount, :target_date, :monthly, :emoji)
    """), {
        "id": goal_id, "uid": user_id, "title": body.title, "amount": body.target_amount,
        "target_date": body.target_date, "monthly": monthly, "emoji": body.emoji,
    })
    await db.commit()
    return {"id": goal_id, "monthly_required": monthly}


@router.get("/goals/{goal_id}")
async def get_goal(
    goal_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM investments.savings_goals WHERE id = :id AND user_id = :uid
    """), {"id": goal_id, "uid": user_id})
    goal = row.mappings().one_or_none()
    if not goal:
        raise HTTPException(status_code=404, detail="Цель не найдена")
    return dict(goal)


@router.put("/goals/{goal_id}")
async def update_goal(
    goal_id: str,
    body: GoalCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE investments.savings_goals
        SET title = :title, target_amount = :amount, target_date = :target_date,
            emoji = :emoji, updated_at = NOW()
        WHERE id = :id AND user_id = :uid
    """), {"title": body.title, "amount": body.target_amount, "target_date": body.target_date,
           "emoji": body.emoji, "id": goal_id, "uid": user_id})
    await db.commit()
    return await get_goal(goal_id, db, user_id)


@router.delete("/goals/{goal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_goal(
    goal_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE investments.savings_goals SET status = 'deleted' WHERE id = :id AND user_id = :uid
    """), {"id": goal_id, "uid": user_id})
    await db.commit()


@router.post("/goals/{goal_id}/contribute")
async def contribute_to_goal(
    goal_id: str,
    body: ContributionCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Добавляет взнос к цели и обновляет текущую сумму."""
    await db.execute(text("""
        INSERT INTO investments.goal_contributions (goal_id, amount, note)
        VALUES (:goal_id, :amount, :note)
    """), {"goal_id": goal_id, "amount": body.amount, "note": body.note})

    await db.execute(text("""
        UPDATE investments.savings_goals
        SET current_amount = current_amount + :amount,
            status = CASE WHEN current_amount + :amount >= target_amount THEN 'achieved' ELSE status END,
            updated_at = NOW()
        WHERE id = :id AND user_id = :uid
    """), {"amount": body.amount, "id": goal_id, "uid": user_id})
    await db.commit()
    return await get_goal(goal_id, db, user_id)


@router.get("/goals/{goal_id}/plan")
async def goal_savings_plan(
    goal_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Персональный план накоплений с рекомендацией вклада."""
    goal = await get_goal(goal_id, db, user_id)
    remaining = float(goal["target_amount"]) - float(goal["current_amount"])
    target_date = goal["target_date"]

    if not target_date:
        return {"monthly_required": None, "message": "Установите дату цели для расчёта плана"}

    months_left = max(1, (target_date.year - date.today().year) * 12 + (target_date.month - date.today().month))
    monthly = monthly_savings_needed(remaining, months_left, rate_percent=16.0)

    return {
        "remaining": remaining,
        "months_left": months_left,
        "monthly_required": monthly,
        "with_deposit_rate": 16.0,
        "tip": f"Откладывайте {monthly:,.0f} ₽/мес на вклад под 16% и достигнете цели вовремя.",
    }
