"""
Расчёт индекса финансового здоровья.

Метрики (итого 100 баллов):
  - savings_rate     (накопительная норма): 30 баллов
  - debt_load        (долговая нагрузка / ПДН): 35 баллов
  - expense_control  (контроль расходов): 35 баллов
"""


def calculate_health_score(
    monthly_income: float,
    monthly_expense: float,
    monthly_debt_payment: float,
    total_debt: float,
    savings: float,
) -> tuple[int, dict]:
    scores = {}

    # --- Накопительная норма (savings rate) ---
    savings_rate = (monthly_income - monthly_expense - monthly_debt_payment) / max(monthly_income, 1) * 100
    if savings_rate >= 20:
        sr_score = 30
    elif savings_rate >= 10:
        sr_score = 20
    elif savings_rate >= 5:
        sr_score = 12
    elif savings_rate >= 0:
        sr_score = 6
    else:
        sr_score = 0
    scores["savings_rate"] = {"score": sr_score, "max": 30, "value": round(savings_rate, 1), "unit": "%"}

    # --- Долговая нагрузка (ПДН по методике ЦБ) ---
    pdn = monthly_debt_payment / max(monthly_income, 1) * 100
    if pdn == 0:
        dl_score = 35
    elif pdn <= 20:
        dl_score = 30
    elif pdn <= 30:
        dl_score = 22
    elif pdn <= 40:
        dl_score = 14
    elif pdn <= 50:
        dl_score = 7
    else:
        dl_score = 0
    scores["debt_load"] = {"score": dl_score, "max": 35, "value": round(pdn, 1), "unit": "%"}

    # --- Контроль расходов (expense ratio) ---
    expense_ratio = monthly_expense / max(monthly_income, 1) * 100
    if expense_ratio <= 50:
        ec_score = 35
    elif expense_ratio <= 65:
        ec_score = 28
    elif expense_ratio <= 75:
        ec_score = 18
    elif expense_ratio <= 90:
        ec_score = 8
    else:
        ec_score = 0
    scores["expense_control"] = {"score": ec_score, "max": 35, "value": round(expense_ratio, 1), "unit": "%"}

    total = sr_score + dl_score + ec_score
    return total, scores


def calculate_credit_traffic_light(
    monthly_income: float,
    monthly_debt_payment: float,
) -> tuple[str, float, str]:
    """Возвращает (цвет светофора, ПДН в %, совет)."""
    pdn = monthly_debt_payment / max(monthly_income, 1) * 100

    if pdn <= 30:
        return "green", round(pdn, 1), "Долговая нагрузка в норме. Новый кредит не создаст рисков."
    elif pdn <= 50:
        return "yellow", round(pdn, 1), (
            "Нагрузка умеренная. Новый кредит возможен, но повышает риски. "
            "Рекомендуем сначала частично погасить существующий долг."
        )
    else:
        return "red", round(pdn, 1), (
            "Высокая долговая нагрузка (ПДН > 50%). По нормативам ЦБ РФ вы в зоне риска. "
            "Брать новые кредиты крайне не рекомендуется. Рассмотрите рефинансирование."
        )
