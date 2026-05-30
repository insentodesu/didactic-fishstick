"""
Классификатор транзакций по категориям.
Работает в два прохода:
  1. Быстрый: словарь мерчант → категория (in-memory, ~3000 паттернов)
  2. Медленный: LLM-сервис для неизвестных мерчантов
"""

import re
from dataclasses import dataclass

# Словарь паттернов: (regex, category_id, confidence)
# category_id соответствует порядку вставки в init.sql:
# 1=еда, 2=транспорт, 3=покупки, 4=развлечения, 5=здоровье,
# 6=ЖКУ, 7=подписки, 8=образование, 9=путешествия, 10=финансы, 12=переводы, 13=прочее

MERCHANT_PATTERNS: list[tuple[re.Pattern, int, float]] = [
    # Еда
    (re.compile(r"макдоналдс|mcdonald|burger king|бургер кинг|kfc|пицца|pizza|суши|sushi|вкусно|вкусвилл|перекрёсток|пятёрочка|магнит|дикси|лента|ашан|metro|метро|продукты|продмаг|универсам", re.I), 1, 0.95),
    (re.compile(r"кафе|cafe|ресторан|restaurant|доставка еды|delivery|яндекс еда|сбермаркет|delivery club|самокат|кухня на районе|додо|dodo|papa john", re.I), 1, 0.90),

    # Транспорт
    (re.compile(r"яндекс.такси|yandex taxi|uber|ситимобил|gett|такси|метрополитен|метро оплата|московское метро|mos\.ru.*транспорт|тройка|оплата проезда|автобус|трамвай|электричка|ржд|rzd|аэроэкспресс", re.I), 2, 0.95),
    (re.compile(r"азс|лукойл|газпромнефть|роснефть|shell|бензин|parkomat|парковка", re.I), 2, 0.85),

    # Покупки
    (re.compile(r"ozon|озон|wildberries|wb\.ru|lamoda|aliexpress|ali express|avito|икеа|ikea|леруа|lerua|castorama|детский мир|спортмастер|декатлон|decathlon|zara|h&m|uniqlo", re.I), 3, 0.95),
    (re.compile(r"dns|днс|эльдорадо|м\.видео|mvideo|re:store|apple store|samsung|mediamarkt|ситилинк|citilink", re.I), 3, 0.90),

    # Развлечения
    (re.compile(r"кинотеатр|cinema|кино|kinopoisk|кинопоиск|netflix|okko|иви|ivi|premier|start\.ru|more\.tv|steam|playstation|xbox|nintendo|twitch|spotify|яндекс музыка|vk музыка|yandex music", re.I), 4, 0.95),

    # Здоровье
    (re.compile(r"аптека|apteka|pharmacy|горздрав|ригла|еаптека|apteki|больница|поликлиника|клиника|стоматолог|дантист|лаборатория|инвитро|гемотест|медси|em-clinic", re.I), 5, 0.95),
    (re.compile(r"фитнес|fitness|спортзал|тренажёрный|world class|х-фит|xfit|планета фитнес|crocus fitness", re.I), 5, 0.85),

    # ЖКУ и связь
    (re.compile(r"мтс|мегафон|билайн|теле2|tele2|ростелеком|beeline|megafon|мобильная связь|интернет|оплата жкх|жкх|коммунальные|газ|электроэнергия|водоканал|тэк|мгтс", re.I), 6, 0.95),

    # Подписки
    (re.compile(r"яндекс плюс|yandex plus|yandex\.plus|подписка|subscription|telegram premium|vk combo|сбер прайм|prime|premium", re.I), 7, 0.90),

    # Образование
    (re.compile(r"skillbox|skillpath|geekbrains|coursera|udemy|stepik|нетология|яндекс практикум|skysmart|учёба|репетитор|школа", re.I), 8, 0.90),

    # Путешествия
    (re.compile(r"авиабилет|авиа|aeroflot|s7|победа|pobeda|utair|аэрофлот|otpusk|ostrovok|booking|airbnb|отель|hotel|хостел|hostel|туристическое", re.I), 9, 0.90),

    # Финансы и кредиты
    (re.compile(r"кредит|ипотека|страховка|страхование|rosgosstrah|ингосстрах|погашение|платёж по кредиту|взнос|займ|mfo|мфо|ломбард", re.I), 10, 0.95),

    # Переводы
    (re.compile(r"перевод|transfer|между счетами|sbp|с2с|card2card|c2c", re.I), 12, 0.85),
]


@dataclass
class CategoryResult:
    category_id: int
    confidence: float
    method: str  # 'dict' | 'llm' | 'default'


def categorize_by_dict(merchant: str) -> CategoryResult | None:
    for pattern, cat_id, confidence in MERCHANT_PATTERNS:
        if pattern.search(merchant):
            return CategoryResult(category_id=cat_id, confidence=confidence, method="dict")
    return None


def categorize_default() -> CategoryResult:
    return CategoryResult(category_id=13, confidence=0.5, method="default")


async def categorize_via_llm(merchant: str, description: str, llm_service_url: str) -> CategoryResult:
    """Отправляет неизвестного мерчанта в LLM-сервис для классификации."""
    import httpx

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                f"{llm_service_url}/classify",
                json={"merchant": merchant, "description": description},
            )
            if resp.status_code == 200:
                data = resp.json()
                return CategoryResult(
                    category_id=data["category_id"],
                    confidence=data["confidence"],
                    method="llm",
                )
    except Exception:
        pass

    return categorize_default()


async def categorize(merchant: str, description: str, llm_service_url: str) -> CategoryResult:
    result = categorize_by_dict(merchant)
    if result and result.confidence >= 0.85:
        return result
    # Низкая уверенность или неизвестный мерчант — идём в LLM
    return await categorize_via_llm(merchant, description, llm_service_url)
