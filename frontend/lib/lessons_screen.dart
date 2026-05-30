import 'package:flutter/material.dart';
import 'ds.dart';

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  int? _openIdx;

  static const _lessons = [
    _Lesson('Что такое ПДН и зачем его считать',
        'ПДН — показатель долговой нагрузки. Это доля твоего ежемесячного дохода, которую ты отдаёшь на погашение кредитов.\n\nПо нормативу ЦБ РФ:\n• < 30% — зелёная зона ✅\n• 30–50% — жёлтая ⚠️\n• > 50% — красная 🔴\n\nЧем ниже ПДН — тем больше свободы в финансах.',
        '📊', 3),
    _Lesson('Как снизить ПДН за 3 шага',
        '1. Закрой самый дорогой кредит первым — даже небольшая переплата сначала выгодна.\n\n2. Не бери новые кредиты, пока ПДН выше 40%.\n\n3. Используй досрочное погашение — даже 5 000 ₽ в месяц дополнительно сокращают срок кредита.',
        '🛠️', 4),
    _Lesson('Правило 50/30/20: простой бюджет',
        'Один из самых простых способов навести порядок в финансах:\n\n50% дохода — на необходимые расходы (жильё, еда, транспорт)\n30% — на желания (кафе, развлечения, одежда)\n20% — на накопления и погашение долга\n\nДаже если сейчас это кажется недостижимым — начни с малого.',
        '💰', 5),
    _Lesson('Рефинансирование: когда оно выгодно',
        'Рефинансирование — замена старого кредита новым с лучшими условиями.\n\nВыгодно если:\n• Ставка нового кредита ниже текущей на 2%+\n• Осталось платить больше года\n• Нет штрафов за досрочное погашение\n\nНе выгодно если остаток долга маленький — переплата на процентах уже близка к минимуму.',
        '🔄', 6),
    _Lesson('Подушка безопасности: с чего начать',
        'Подушка безопасности — деньги на 3–6 месяцев базовых расходов.\n\nПочему важно:\n• Защищает от неожиданных трат\n• Снижает стресс\n• Не нужно брать кредит «на всякий случай»\n\nНачни с маленькой цели — 30 000 ₽. Откладывай по 3 000 ₽/мес — через 10 месяцев цель достигнута.',
        '🛡️', 5),
    _Lesson('Как читать банковскую выписку',
        'Выписка — полная история операций по счёту. Там есть:\n\n• Дата и время операции\n• Сумма списания или зачисления\n• Название магазина или получателя\n• Остаток на счёте\n\nЗагружай выписку раз в месяц — Бади автоматически категоризирует все траты и покажет, куда уходят деньги.',
        '📋', 4),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              children: [
                FpFadeIn(delay: Duration.zero, child: FpOverline('Уроки')),
                const SizedBox(height: 8),
                FpFadeIn(delay: const Duration(milliseconds: 40), child: Text('6 уроков · 2–5 минут каждый', style: dsSmall(color: kInk2))),
                const SizedBox(height: 16),
                FpFadeIn(delay: const Duration(milliseconds: 80), child: _progressCard()),
                const SizedBox(height: 16),
                for (var i = 0; i < _lessons.length; i++) ...[
                  FpFadeIn(delay: Duration(milliseconds: 120 + i * 60), child: _lessonCard(_lessons[i], i, _openIdx == i)),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressCard() {
    final total = _lessons.length;
    const done = 2;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Прогресс', style: dsH3()),
            FpChip(child: Text('$done / $total'), bg: kGreenBg, color: kGreen),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 12,
              backgroundColor: kGreenBg,
              valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
            ),
          ),
          const SizedBox(height: 8),
          Text('Пройди урок — покорми Бади 🦴', style: dsSmall(color: kInk2)),
        ],
      ),
    );
  }

  Widget _lessonCard(_Lesson l, int i, bool open) {
    final done = i < 2;
    return FpCard(
      onTap: () => setState(() => _openIdx = open ? null : i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: done ? kGreenBg : kGoldTint,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(l.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (done) FpOverline('ПРОЙДЕНО', color: kGreen),
              Text(l.title, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: kInk1)),
              const SizedBox(height: 2),
              Text('${l.minutes} мин', style: dsCaption(color: kInk3)),
            ])),
            Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: kInk3, size: 20),
          ]),
          if (open) ...[
            const SizedBox(height: 14),
            const Divider(color: kLine, height: 1),
            const SizedBox(height: 14),
            Text(l.content, style: dsBody(color: kInk1)),
            const SizedBox(height: 14),
            FpButton.gold(
              full: true,
              onPressed: () {
                setState(() => _openIdx = null);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Урок "${l.title}" пройден! Бади получил +20 🦴'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: kGreen,
                ));
              },
              child: Text(done ? 'Пройти снова' : 'Завершить урок'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Lesson {
  final String title, content, emoji;
  final int minutes;
  const _Lesson(this.title, this.content, this.emoji, this.minutes);
}
