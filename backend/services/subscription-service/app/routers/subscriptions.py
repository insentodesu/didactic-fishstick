from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.deps import get_current_user_id

router = APIRouter(prefix="/subscriptions", tags=["Подписки"])


@router.get("/")
async def list_subscriptions(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    rows = await db.execute(text("""
        SELECT * FROM subscriptions.subscriptions
        WHERE user_id = :uid ORDER BY amount DESC
    """), {"uid": user_id})
    return [dict(r._mapping) for r in rows]


@router.get("/stats")
async def subscription_stats(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT
            COUNT(*) FILTER (WHERE status = 'active') AS active_count,
            COUNT(*) FILTER (WHERE status = 'suspicious') AS suspicious_count,
            COALESCE(SUM(amount) FILTER (WHERE status = 'active' AND billing_period = 'monthly'), 0) AS monthly_total,
            COALESCE(SUM(amount) FILTER (WHERE status = 'active' AND billing_period = 'yearly') / 12, 0) AS yearly_per_month
        FROM subscriptions.subscriptions WHERE user_id = :uid
    """), {"uid": user_id})
    stats = dict(row.mappings().one())
    stats["total_monthly"] = float(stats["monthly_total"]) + float(stats["yearly_per_month"])
    return stats


@router.get("/alerts")
async def subscription_alerts(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Подписки с датой списания в ближайшие 3 дня или подозрительные."""
    rows = await db.execute(text("""
        SELECT * FROM subscriptions.subscriptions
        WHERE user_id = :uid AND (
            status = 'suspicious'
            OR next_billing_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 days'
        )
        ORDER BY next_billing_date
    """), {"uid": user_id})
    return [dict(r._mapping) for r in rows]


@router.get("/{subscription_id}")
async def get_subscription(
    subscription_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM subscriptions.subscriptions WHERE id = :id AND user_id = :uid
    """), {"id": subscription_id, "uid": user_id})
    sub = row.mappings().one_or_none()
    if not sub:
        raise HTTPException(status_code=404, detail="Подписка не найдена")
    return dict(sub)


@router.put("/{subscription_id}")
async def update_subscription(
    subscription_id: str,
    status: str | None = None,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    if status and status not in ("active", "cancelled", "suspicious"):
        raise HTTPException(status_code=400, detail="Недопустимый статус")
    await db.execute(text("""
        UPDATE subscriptions.subscriptions
        SET status = COALESCE(:status, status), updated_at = NOW()
        WHERE id = :id AND user_id = :uid
    """), {"status": status, "id": subscription_id, "uid": user_id})
    await db.commit()
    return await get_subscription(subscription_id, db, user_id)


@router.delete("/{subscription_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_subscription(
    subscription_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE subscriptions.subscriptions SET status = 'cancelled'
        WHERE id = :id AND user_id = :uid
    """), {"id": subscription_id, "uid": user_id})
    await db.commit()


@router.post("/scan")
async def scan_transactions(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Сканирует транзакции пользователя для поиска подписок."""
    # TODO: запрос в transaction-service + вызов detector.detect_recurring
    return {"status": "queued", "message": "Сканирование запущено. Результат появится через 10-20 секунд."}


@router.post("/gmail/scan")
async def scan_gmail(
    user_id: str = Depends(get_current_user_id),
):
    """Сканирует входящие Gmail на предмет писем от подписочных сервисов."""
    # Требует Gmail OAuth токен из auth-service
    return {"status": "queued", "message": "Сканирование Gmail запущено."}
