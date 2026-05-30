"""
Движок тамагочи.

Механика:
  - Питомец теряет hunger на 5 очков в час (настраивается)
  - Кормление = пользователь фиксирует сэкономленную сумму
  - 100 ₽ экономии = +10 hunger, +5 exp
  - При hunger=0 питомец "засыпает" (is_alive=False)
  - Уровень растёт каждые 100 exp
  - Уровень 5 = открывает достижение 'tamagochi_lvl5'
"""

from datetime import datetime, timezone
from math import floor

from app.config import settings


def calculate_hunger_decay(last_decay_at: datetime) -> int:
    """Рассчитывает потерю голода с момента последнего обновления."""
    now = datetime.now(timezone.utc)
    hours_passed = (now - last_decay_at.replace(tzinfo=timezone.utc)).total_seconds() / 3600
    return floor(hours_passed * settings.tamagochi_hunger_decay_per_hour)


def apply_feeding(hunger: int, experience: int, level: int, amount_rub: float) -> dict:
    """
    Применяет кормление. Возвращает новые значения и список событий.

    amount_rub: сумма сэкономленного в рублях
    """
    hunger_restored = int(amount_rub / 100 * settings.tamagochi_hunger_per_100rub)
    exp_gained = int(amount_rub / 100 * settings.tamagochi_exp_per_100rub)

    new_hunger = min(100, hunger + hunger_restored)
    new_exp = experience + exp_gained
    new_level = level

    events = []
    # Проверяем левелап
    while new_exp >= settings.tamagochi_level_up_exp * new_level:
        new_exp -= settings.tamagochi_level_up_exp * new_level
        new_level += 1
        events.append({"type": "level_up", "new_level": new_level})

    return {
        "hunger": new_hunger,
        "experience": new_exp,
        "level": new_level,
        "hunger_restored": hunger_restored,
        "exp_gained": exp_gained,
        "events": events,
    }


def apply_decay(hunger: int, decay: int) -> tuple[int, bool]:
    """Применяет накопленный распад голода. Возвращает (новый_hunger, is_alive)."""
    new_hunger = max(0, hunger - decay)
    return new_hunger, new_hunger > 0


SPECIES_SPRITES = {
    "cat": {
        "alive_happy": "🐱",
        "alive_hungry": "😿",
        "sleeping": "😴",
    },
    "dog": {
        "alive_happy": "🐶",
        "alive_hungry": "🐶",
        "sleeping": "😴",
    },
    "dragon": {
        "alive_happy": "🐲",
        "alive_hungry": "🐉",
        "sleeping": "😴",
    },
}


def get_sprite(species: str, hunger: int, is_alive: bool) -> str:
    sprites = SPECIES_SPRITES.get(species, SPECIES_SPRITES["cat"])
    if not is_alive:
        return sprites["sleeping"]
    if hunger < 30:
        return sprites["alive_hungry"]
    return sprites["alive_happy"]
