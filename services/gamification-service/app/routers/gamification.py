from datetime import date, datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.db.session import get_db
from app.services.deps import get_current_user_id
from app.services.tamagochi_engine import apply_feeding, apply_decay, calculate_hunger_decay, get_sprite

router = APIRouter(prefix="/gamification", tags=["Геймификация"])


# ========================= ТАМАГОЧИ =========================

@router.get("/tamagochi")
async def get_tamagochi(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Возвращает текущее состояние питомца с применением накопленного распада."""
    row = await db.execute(
        text("SELECT * FROM gamification.tamagochi WHERE user_id = :uid"),
        {"uid": user_id},
    )
    pet = row.mappings().one_or_none()

    if not pet:
        # Создаём питомца при первом обращении
        await db.execute(text("""
            INSERT INTO gamification.tamagochi (user_id)
            VALUES (:uid)
        """), {"uid": user_id})
        await db.commit()
        return {"message": "Питомец создан!", "hunger": 100, "level": 1, "is_alive": True, "sprite": "🐱"}

    # Применяем распад голода
    decay = calculate_hunger_decay(pet["last_hunger_decay_at"])
    new_hunger, is_alive = apply_decay(pet["hunger"], decay)

    if decay > 0:
        await db.execute(text("""
            UPDATE gamification.tamagochi
            SET hunger = :hunger, is_alive = :alive, last_hunger_decay_at = NOW()
            WHERE user_id = :uid
        """), {"hunger": new_hunger, "alive": is_alive, "uid": user_id})
        await db.commit()

    sprite = get_sprite(pet["species"], new_hunger, is_alive)

    return {
        "id": str(pet["id"]),
        "name": pet["name"],
        "species": pet["species"],
        "level": pet["level"],
        "experience": pet["experience"],
        "hunger": new_hunger,
        "happiness": pet["happiness"],
        "health": pet["health"],
        "is_alive": is_alive,
        "sprite": sprite,
        "total_fed_amount": float(pet["total_fed_amount"]),
        "last_fed_at": pet["last_fed_at"].isoformat() if pet["last_fed_at"] else None,
    }


@router.post("/tamagochi/feed")
async def feed_tamagochi(
    amount: float = Query(..., gt=0, description="Сумма сэкономленного в рублях"),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Кормит питомца сэкономленными деньгами."""
    row = await db.execute(
        text("SELECT * FROM gamification.tamagochi WHERE user_id = :uid"),
        {"uid": user_id},
    )
    pet = row.mappings().one_or_none()
    if not pet:
        raise HTTPException(status_code=404, detail="Питомец не найден. Получите его через GET /gamification/tamagochi")

    if not pet["is_alive"]:
        raise HTTPException(status_code=400, detail="Питомец спит. Покормите его, чтобы разбудить!")

    result = apply_feeding(pet["hunger"], pet["experience"], pet["level"], amount)

    await db.execute(text("""
        UPDATE gamification.tamagochi
        SET hunger = :hunger, experience = :exp, level = :level,
            total_fed_amount = total_fed_amount + :amount,
            last_fed_at = NOW(), last_hunger_decay_at = NOW()
        WHERE user_id = :uid
    """), {
        "hunger": result["hunger"],
        "exp": result["experience"],
        "level": result["level"],
        "amount": amount,
        "uid": user_id,
    })

    # Записываем в историю кормления
    await db.execute(text("""
        INSERT INTO gamification.feeding_history (user_id, amount, hunger_restored, exp_gained)
        VALUES (:uid, :amount, :hunger, :exp)
    """), {"uid": user_id, "amount": amount, "hunger": result["hunger_restored"], "exp": result["exp_gained"]})

    await db.commit()

    return {
        "hunger": result["hunger"],
        "experience": result["experience"],
        "level": result["level"],
        "hunger_restored": result["hunger_restored"],
        "exp_gained": result["exp_gained"],
        "events": result["events"],
        "sprite": get_sprite(pet["species"], result["hunger"], True),
    }


@router.get("/tamagochi/history")
async def feeding_history(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(20, ge=1, le=100),
):
    rows = await db.execute(text("""
        SELECT amount, hunger_restored, exp_gained, fed_at
        FROM gamification.feeding_history
        WHERE user_id = :uid
        ORDER BY fed_at DESC
        LIMIT :limit
    """), {"uid": user_id, "limit": limit})
    return [dict(r._mapping) for r in rows]


# ========================= СТРИКИ =========================

@router.get("/streak")
async def get_streak(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(
        text("SELECT * FROM gamification.streaks WHERE user_id = :uid"),
        {"uid": user_id},
    )
    streak = row.mappings().one_or_none()
    if not streak:
        return {"current_streak": 0, "longest_streak": 0, "last_check_in": None}
    return dict(streak)


@router.post("/daily-checkin")
async def daily_checkin(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Ежедневный чек-ин. Обновляет стрик, начисляет бонус питомцу."""
    today = date.today()

    row = await db.execute(
        text("SELECT * FROM gamification.streaks WHERE user_id = :uid"),
        {"uid": user_id},
    )
    streak = row.mappings().one_or_none()

    if streak and streak["last_check_in"] == today:
        return {"message": "Уже зарегистрировано сегодня", "current_streak": streak["current_streak"]}

    if not streak:
        await db.execute(text("""
            INSERT INTO gamification.streaks (user_id, current_streak, longest_streak, last_check_in, total_check_ins)
            VALUES (:uid, 1, 1, :today, 1)
        """), {"uid": user_id, "today": today})
        new_streak = 1
    else:
        from datetime import timedelta
        yesterday = today - timedelta(days=1)
        if streak["last_check_in"] == yesterday:
            new_streak = streak["current_streak"] + 1
        else:
            new_streak = 1  # стрик сброшен

        new_longest = max(new_streak, streak["longest_streak"])
        await db.execute(text("""
            UPDATE gamification.streaks
            SET current_streak = :streak, longest_streak = :longest,
                last_check_in = :today, total_check_ins = total_check_ins + 1
            WHERE user_id = :uid
        """), {"streak": new_streak, "longest": new_longest, "today": today, "uid": user_id})

    await db.commit()
    return {"current_streak": new_streak, "bonus": "Питомец получил +5 настроения!"}


# ========================= ДОСТИЖЕНИЯ =========================

@router.get("/achievements")
async def list_all_achievements(db: AsyncSession = Depends(get_db)):
    rows = await db.execute(text("SELECT * FROM gamification.achievements ORDER BY points"))
    return [dict(r._mapping) for r in rows]


@router.get("/achievements/unlocked")
async def unlocked_achievements(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    rows = await db.execute(text("""
        SELECT a.*, ua.earned_at
        FROM gamification.user_achievements ua
        JOIN gamification.achievements a ON a.id = ua.achievement_id
        WHERE ua.user_id = :uid
        ORDER BY ua.earned_at DESC
    """), {"uid": user_id})
    return [dict(r._mapping) for r in rows]


# ========================= ЗАДАНИЯ =========================

@router.get("/challenges")
async def daily_challenges(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Ежедневные задания пользователя. Генерируются автоматически если отсутствуют."""
    today = date.today()
    rows = await db.execute(text("""
        SELECT * FROM gamification.daily_challenges
        WHERE user_id = :uid AND challenge_date = :today
    """), {"uid": user_id, "today": today})
    challenges = [dict(r._mapping) for r in rows]

    if not challenges:
        # Генерируем базовый набор заданий
        default_challenges = [
            ("Проверьте баланс", "Откройте дашборд и посмотрите, сколько осталось до конца месяца", 10, 20),
            ("Найдите подписку", "Перейдите в раздел подписок и проверьте актуальность", 15, 25),
            ("Покормите питомца", "Зафиксируйте любую экономию сегодня", 20, 30),
        ]
        for title, desc, points, hunger in default_challenges:
            await db.execute(text("""
                INSERT INTO gamification.daily_challenges
                    (user_id, challenge_date, title, description, reward_points, reward_hunger)
                VALUES (:uid, :today, :title, :desc, :points, :hunger)
                ON CONFLICT DO NOTHING
            """), {"uid": user_id, "today": today, "title": title, "desc": desc, "points": points, "hunger": hunger})
        await db.commit()

        rows = await db.execute(text("""
            SELECT * FROM gamification.daily_challenges
            WHERE user_id = :uid AND challenge_date = :today
        """), {"uid": user_id, "today": today})
        challenges = [dict(r._mapping) for r in rows]

    return challenges


@router.post("/challenges/{challenge_id}/complete")
async def complete_challenge(
    challenge_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(text("""
        SELECT * FROM gamification.daily_challenges
        WHERE id = :id AND user_id = :uid AND is_completed = false
    """), {"id": challenge_id, "uid": user_id})
    challenge = row.mappings().one_or_none()
    if not challenge:
        raise HTTPException(status_code=404, detail="Задание не найдено или уже выполнено")

    await db.execute(text("""
        UPDATE gamification.daily_challenges
        SET is_completed = true, completed_at = NOW()
        WHERE id = :id
    """), {"id": challenge_id})

    # Начисляем награду питомцу
    await db.execute(text("""
        UPDATE gamification.tamagochi
        SET hunger = LEAST(100, hunger + :hunger), experience = experience + :exp
        WHERE user_id = :uid
    """), {"hunger": challenge["reward_hunger"], "exp": challenge["reward_points"], "uid": user_id})

    await db.commit()
    return {"status": "completed", "reward_points": challenge["reward_points"], "reward_hunger": challenge["reward_hunger"]}


# ========================= ЛИГИ =========================

@router.get("/leagues")
async def my_league(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    from datetime import date
    season = date.today().isocalendar().week  # номер недели как сезон

    row = await db.execute(text("""
        SELECT * FROM gamification.leagues WHERE user_id = :uid AND season = :season
    """), {"uid": user_id, "season": season})
    league = row.mappings().one_or_none()
    if not league:
        return {"league_tier": "bronze", "points": 0, "rank": None, "season": season}
    return dict(league)


@router.get("/leaderboard")
async def leaderboard(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(20, ge=5, le=100),
):
    from datetime import date
    season = date.today().isocalendar().week

    rows = await db.execute(text("""
        SELECT l.user_id, l.points, l.league_tier,
               ROW_NUMBER() OVER (ORDER BY l.points DESC) AS rank
        FROM gamification.leagues l
        WHERE l.season = :season
        ORDER BY l.points DESC
        LIMIT :limit
    """), {"season": season, "limit": limit})
    return [dict(r._mapping) for r in rows]


@router.get("/points")
async def my_points(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Суммарные очки пользователя из достижений."""
    row = await db.execute(text("""
        SELECT COALESCE(SUM(a.points), 0) AS total_points
        FROM gamification.user_achievements ua
        JOIN gamification.achievements a ON a.id = ua.achievement_id
        WHERE ua.user_id = :uid
    """), {"uid": user_id})
    return {"total_points": row.scalar()}
