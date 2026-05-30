import asyncio
import json
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.deps import get_current_user_id

router = APIRouter(prefix="/notifications", tags=["Уведомления"])


@router.get("/")
async def list_notifications(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    unread_only: bool = Query(False),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    where = "user_id = :uid"
    if unread_only:
        where += " AND is_read = false"
    offset = (page - 1) * page_size

    rows = await db.execute(text(f"""
        SELECT * FROM notifications.notifications
        WHERE {where}
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """), {"uid": user_id, "limit": page_size, "offset": offset})
    return [dict(r._mapping) for r in rows]


@router.get("/unread-count")
async def unread_count(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT COUNT(*) FROM notifications.notifications WHERE user_id = :uid AND is_read = false
    """), {"uid": user_id})
    return {"count": row.scalar()}


@router.get("/{notification_id}")
async def get_notification(
    notification_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM notifications.notifications WHERE id = :id AND user_id = :uid
    """), {"id": notification_id, "uid": user_id})
    n = row.mappings().one_or_none()
    if not n:
        raise HTTPException(status_code=404, detail="Уведомление не найдено")
    return dict(n)


@router.put("/{notification_id}/read")
async def mark_read(
    notification_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE notifications.notifications SET is_read = true WHERE id = :id AND user_id = :uid
    """), {"id": notification_id, "uid": user_id})
    await db.commit()
    return {"status": "ok"}


@router.put("/read-all", status_code=200)
async def mark_all_read(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        UPDATE notifications.notifications SET is_read = true WHERE user_id = :uid AND is_read = false
    """), {"uid": user_id})
    await db.commit()
    return {"status": "ok"}


@router.delete("/{notification_id}", status_code=204)
async def delete_notification(
    notification_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        DELETE FROM notifications.notifications WHERE id = :id AND user_id = :uid
    """), {"id": notification_id, "uid": user_id})
    await db.commit()


@router.get("/preferences/me")
async def get_preferences(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM notifications.preferences WHERE user_id = :uid
    """), {"uid": user_id})
    prefs = row.mappings().one_or_none()
    if not prefs:
        return {"user_id": user_id, "subscription_alerts": True, "goal_progress": True,
                "tamagochi_hunger": True, "anomaly_alerts": True, "weekly_digest": True}
    return dict(prefs)


@router.put("/preferences/me")
async def update_preferences(
    subscription_alerts: bool = True,
    goal_progress: bool = True,
    tamagochi_hunger: bool = True,
    anomaly_alerts: bool = True,
    weekly_digest: bool = True,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    await db.execute(text("""
        INSERT INTO notifications.preferences
            (user_id, subscription_alerts, goal_progress, tamagochi_hunger, anomaly_alerts, weekly_digest)
        VALUES (:uid, :sub, :goal, :tama, :anomaly, :digest)
        ON CONFLICT (user_id) DO UPDATE SET
            subscription_alerts = :sub, goal_progress = :goal, tamagochi_hunger = :tama,
            anomaly_alerts = :anomaly, weekly_digest = :digest, updated_at = NOW()
    """), {"uid": user_id, "sub": subscription_alerts, "goal": goal_progress,
           "tama": tamagochi_hunger, "anomaly": anomaly_alerts, "digest": weekly_digest})
    await db.commit()
    return {"status": "updated"}


# SSE вместо WebSocket — проще и не требует доп. зависимостей
@router.get("/stream")
async def notification_stream(request: Request, user_id: str = Depends(get_current_user_id)):
    """
    Server-Sent Events поток для real-time уведомлений.
    Клиент подключается и получает события без polling.
    """
    async def event_generator() -> AsyncGenerator[str, None]:
        while True:
            if await request.is_disconnected():
                break
            # В продакшне: подписка на Redis pub/sub канал user_{user_id}_notifications
            yield f"data: {json.dumps({'type': 'ping', 'user_id': user_id})}\n\n"
            await asyncio.sleep(30)

    return StreamingResponse(event_generator(), media_type="text/event-stream")
