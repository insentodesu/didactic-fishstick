import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF8A8678);
const _faint = Color(0xFFA09C8E);
const _green = Color(0xFF2A4D3E);
const _petAccent = Color(0xFF5B4FBE);
const _petAccentLite = Color(0xFF7B6FDE);

// ---------------------------------------------------------------------------
// Данные об эволюции
// ---------------------------------------------------------------------------
class _Stage {
  final String emoji;
  final String name;
  final int threshold;
  const _Stage(this.emoji, this.name, this.threshold);
}

const _stages = [
  _Stage('🥚', 'Яйцо', 0),
  _Stage('🐣', 'Птенец', 10000),
  _Stage('🐥', 'Цыплёнок', 50000),
  _Stage('🐦', 'Птица', 150000),
  _Stage('🦅', 'Орёл', 500000),
];

// ---------------------------------------------------------------------------
// Состояние здоровья питомца
// ---------------------------------------------------------------------------
enum _Health { healthy, sick, critical }

// ---------------------------------------------------------------------------

class TamagotchiScreen extends StatefulWidget {
  const TamagotchiScreen({super.key});
  @override
  State<TamagotchiScreen> createState() => _TamagotchiScreenState();
}

class _TamagotchiScreenState extends State<TamagotchiScreen> {
  String _petName = '';

  // TODO: подключить к данным транзакций HomeScreen
  final double _totalSaved = 0;       // накопленная сумма
  final double _savingsRate = 0.0;    // доля дохода в сбережениях
  final double _balanceScore = 0.47;  // доходы / (доходы + |расходы|)
  final double _trackingScore = 0.71; // регулярность ведения учёта

  // TODO: вычислять из SharedPreferences ('last_financial_activity')
  // и обновлять при добавлении дохода/сбережений в HomeScreen
  final int _daysSinceActive = 0;

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  _Health get _health {
    if (_daysSinceActive >= 14) return _Health.critical;
    if (_daysSinceActive >= 7) return _Health.sick;
    return _Health.healthy;
  }

  // При сбросе прогресс обнуляется
  double get _effectiveSaved =>
      _health == _Health.critical ? 0 : _totalSaved;

  // Порог для следующего уровня повышается на 50% если питомец болен
  double _adjustedThreshold(int raw) =>
      _health == _Health.sick ? raw * 1.5 : raw.toDouble();

  int get _stageIndex {
    for (var i = _stages.length - 1; i >= 0; i--) {
      if (_effectiveSaved >= _stages[i].threshold) return i;
    }
    return 0;
  }

  _Stage get _stage => _stages[_stageIndex];

  double get _progressToNext {
    final idx = _stageIndex;
    if (idx >= _stages.length - 1) return 1.0;
    final from = _stages[idx].threshold.toDouble();
    final to = _adjustedThreshold(_stages[idx + 1].threshold);
    return ((_effectiveSaved - from) / (to - from)).clamp(0.0, 1.0);
  }

  double? get _amountToNext {
    final idx = _stageIndex;
    if (idx >= _stages.length - 1) return null;
    return _adjustedThreshold(_stages[idx + 1].threshold) - _effectiveSaved;
  }

  int get _daysToReset => (14 - _daysSinceActive).clamp(0, 14);

  // ---------------------------------------------------------------------------
  // Status card getters (healthy state only)
  // ---------------------------------------------------------------------------

  String get _statusTitle {
    if (_savingsRate == 0) return 'Питомец голоден';
    if (_savingsRate < 0.10) return 'Питомец немного сыт';
    if (_savingsRate < 0.20) return 'Питомец доволен';
    return 'Питомец счастлив';
  }

  String get _statusBody {
    if (_savingsRate == 0) {
      return 'Начните откладывать часть дохода — питомец ждёт первой порции.';
    }
    if (_savingsRate < 0.10) {
      return 'Откладывайте хотя бы 10% дохода, чтобы питомец рос быстрее.';
    }
    if (_savingsRate < 0.20) {
      return 'Хорошая норма! Увеличьте сбережения до 20% для ускорения роста.';
    }
    return 'Отличная финансовая дисциплина — питомец активно развивается!';
  }

  Color get _statusColor {
    if (_savingsRate == 0) return const Color(0xFFE57373);
    if (_savingsRate < 0.10) return const Color(0xFFFFB74D);
    if (_savingsRate < 0.20) return const Color(0xFF81C784);
    return const Color(0xFF4CAF50);
  }

  IconData get _statusIcon {
    if (_savingsRate == 0) return Icons.sentiment_very_dissatisfied_outlined;
    if (_savingsRate < 0.10) return Icons.sentiment_neutral_outlined;
    if (_savingsRate < 0.20) return Icons.sentiment_satisfied_outlined;
    return Icons.sentiment_very_satisfied_outlined;
  }

  // ---------------------------------------------------------------------------
  // Pet card gradient changes with health
  // ---------------------------------------------------------------------------

  List<Color> get _cardGradient {
    switch (_health) {
      case _Health.sick:
        return [const Color(0xFFA0622A), const Color(0xFFC07840)];
      case _Health.critical:
        return [const Color(0xFF5A5A5A), const Color(0xFF787878)];
      case _Health.healthy:
        return [_petAccent, _petAccentLite];
    }
  }

  Color get _cardShadow {
    switch (_health) {
      case _Health.sick:
        return const Color(0xFFA0622A);
      case _Health.critical:
        return const Color(0xFF5A5A5A);
      case _Health.healthy:
        return _petAccent;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _petName = prefs.getString('pet_name') ?? '');
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _petName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Имя питомца',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Например, Монетка',
            hintStyle: const TextStyle(color: _faint),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFEEEEEE), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _green, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена',
                style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pet_name', result);
    setState(() => _petName = result);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              _header(),
              const SizedBox(height: 24),
              _petCard(),
              if (_health != _Health.healthy) ...[
                const SizedBox(height: 16),
                _alertCard(),
              ],
              const SizedBox(height: 16),
              _statusCard(),
              const SizedBox(height: 16),
              _statsCard(),
              const SizedBox(height: 16),
              _howToCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Финансовый питомец',
                    style: TextStyle(fontSize: 14, color: _muted)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _editName,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _petName.isNotEmpty ? _petName : 'Дать имя',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: _petName.isNotEmpty ? _ink : _faint,
                              letterSpacing: -0.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined, size: 17, color: _muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _editName,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _cardShadow.withValues(alpha: .15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _health == _Health.critical ? '🥚' : _stage.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
        ],
      );

  Widget _petCard() {
    final toNext = _amountToNext;
    final isCritical = _health == _Health.critical;
    final isSick = _health == _Health.sick;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _cardGradient,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _cardShadow.withValues(alpha: .30),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCritical
                      ? 'Прогресс сброшен'
                      : 'Уровень ${_stageIndex + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Text(
                isCritical
                    ? 'Накоплено: ${_fmt(0)}'
                    : 'Накоплено: ${_fmt(_totalSaved)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  isCritical ? '🥚' : _stage.emoji,
                  style: const TextStyle(fontSize: 60),
                ),
              ),
              if (isSick || isCritical)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Text(
                    isCritical ? '💀' : '🤒',
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isCritical ? 'Яйцо' : _stage.name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          if (isSick) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Болен — требуется усиленный уход',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
          if (isCritical) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Начните развитие заново',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 14),
          if (!isCritical && toNext != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSick
                      ? 'До следующего уровня (×1.5)'
                      : 'До следующего уровня',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 12),
                ),
                Text(
                  _fmt(toNext),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progressToNext,
                backgroundColor: Colors.white.withValues(alpha: .2),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 7,
              ),
            ),
          ] else if (!isCritical && toNext == null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Максимальный уровень!',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _alertCard() {
    final isCritical = _health == _Health.critical;

    final bgColor = isCritical
        ? const Color(0xFFFFE8E8)
        : const Color(0xFFFFF4E0);
    final borderColor = isCritical
        ? const Color(0xFFE57373)
        : const Color(0xFFFFB74D);
    final iconColor = isCritical
        ? const Color(0xFFC62828)
        : const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCritical ? Icons.error_outline : Icons.warning_amber_outlined,
                color: iconColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCritical ? 'Прогресс сброшен' : 'Питомец заболел',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: iconColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isCritical
                ? 'Питомец долго болел и потерял весь накопленный прогресс. Развитие начинается заново с 🥚.'
                : 'Вы не проявляли финансовой активности $_daysSinceActive дн. Питомец нуждается в усиленном уходе.',
            style: TextStyle(
                fontSize: 12.5, color: iconColor.withValues(alpha: .8), height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 1,
            color: borderColor.withValues(alpha: .4),
          ),
          const SizedBox(height: 14),
          if (isCritical) ...[
            _alertRow(Icons.savings_outlined, iconColor,
                'Начните откладывать деньги снова'),
            const SizedBox(height: 8),
            _alertRow(Icons.bar_chart_outlined, iconColor,
                'Ведите активный учёт расходов и доходов'),
            const SizedBox(height: 8),
            _alertRow(Icons.trending_up, iconColor,
                'Инвестируйте — рост будет быстрее прежнего'),
          ] else ...[
            _alertRow(Icons.double_arrow, iconColor,
                'Откладывайте вдвойне обычного — порог уровня ×1.5'),
            const SizedBox(height: 8),
            _alertRow(Icons.timer_outlined, iconColor,
                'До сброса прогресса: $_daysToReset дн. — успейте!'),
          ],
        ],
      ),
    );
  }

  Widget _alertRow(IconData icon, Color color, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    color: color.withValues(alpha: .85),
                    height: 1.35)),
          ),
        ],
      );

  Widget _statusCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _statusColor.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: _statusColor.withValues(alpha: .25), width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_statusIcon, color: _statusColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusTitle,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _statusColor)),
                  const SizedBox(height: 3),
                  Text(_statusBody,
                      style: const TextStyle(
                          fontSize: 12.5, color: _muted, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _statsCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Финансовые показатели',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink)),
            const SizedBox(height: 16),
            _statRow('💰', 'Норма сбережений', _savingsRate,
                const Color(0xFF7FB685)),
            const SizedBox(height: 14),
            _statRow('📈', 'Баланс доходов', _balanceScore,
                const Color(0xFF85C7C0)),
            const SizedBox(height: 14),
            _statRow('🎯', 'Активность учёта', _trackingScore,
                const Color(0xFFA0A0D0)),
          ],
        ),
      );

  Widget _statRow(String emoji, String label, double value, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
              ]),
              Text('${(value * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: _faint)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: const Color(0xFFF0EEEA),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      );

  Widget _howToCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Как растить питомца',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink)),
            const SizedBox(height: 14),
            _howToRow('💰', 'Откладывайте деньги',
                'Кормит питомца и повышает уровень',
                const Color(0xFF7FB685)),
            const Divider(color: Color(0xFFF0EEEA), height: 1),
            _howToRow('📊', 'Ведите учёт трат',
                'Поддерживает активность питомца',
                const Color(0xFF85C7C0)),
            const Divider(color: Color(0xFFF0EEEA), height: 1),
            _howToRow('🌱', 'Инвестируйте доходы',
                'Ускоряет рост и эволюцию питомца',
                const Color(0xFFA0A0D0)),
          ],
        ),
      );

  Widget _howToRow(
          String emoji, String title, String subtitle, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      );

  String _fmt(double n) => n
          .toStringAsFixed(0)
          .replaceAllMapped(
              RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ') +
      ' ₽';
}
