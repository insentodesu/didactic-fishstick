"""Калькулятор сложных процентов."""

from math import pow


def compound_interest(
    principal: float,
    rate_percent: float,
    term_days: int,
    capitalization: bool = False,
    periods_per_year: int = 12,
) -> dict:
    """
    Рассчитывает итоговую сумму и доход по вкладу.

    principal: начальная сумма (₽)
    rate_percent: годовая ставка (%)
    term_days: срок вклада в днях
    capitalization: начисление процентов на проценты
    periods_per_year: количество капитализаций в год (12 = ежемесячно)
    """
    rate = rate_percent / 100
    years = term_days / 365

    if capitalization:
        # A = P * (1 + r/n)^(n*t)
        n = periods_per_year
        final = principal * pow(1 + rate / n, n * years)
    else:
        # Простые проценты
        final = principal * (1 + rate * years)

    income = final - principal
    effective_rate = (income / principal) * (365 / term_days) * 100

    return {
        "principal": round(principal, 2),
        "final_amount": round(final, 2),
        "income": round(income, 2),
        "effective_rate_percent": round(effective_rate, 2),
        "term_days": term_days,
        "capitalization": capitalization,
    }


def monthly_savings_needed(target: float, months: int, rate_percent: float = 0.0) -> float:
    """Сколько откладывать в месяц для достижения цели."""
    if rate_percent == 0 or months == 0:
        return target / max(months, 1)
    r = rate_percent / 100 / 12
    # PMT formula
    pmt = target * r / ((pow(1 + r, months) - 1))
    return round(pmt, 2)
