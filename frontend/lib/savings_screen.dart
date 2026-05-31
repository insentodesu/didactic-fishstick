import 'package:flutter/material.dart';

import 'api_client.dart' as api;
import 'ds.dart';

class SavingsScreen extends StatefulWidget {
  final bool demoMode;
  const SavingsScreen({super.key, this.demoMode = false});
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  _SavingsData? _data;
  bool _loading = true;
  late List<_GoalItem> _demoGoals;

  @override
  void initState() {
    super.initState();
    _demoGoals = [
      const _GoalItem(title: 'Подушка безопасности', emoji: '🛡️', current: 62000, target: 150000, monthlyRequired: 12000, deadline: 'марту 2027'),
    ];
    _load();
  }

  Future<void> _load() async {
    if (widget.demoMode) {
      final demo = _SavingsData.demo();
      if (mounted) setState(() {
        _data = _SavingsData(highDebt: demo.highDebt, goals: List.from(_demoGoals), deposits: demo.deposits, subStats: demo.subStats);
        _loading = false;
      });
      return;
    }
    try {
      final deposits = await api.getDeposits();
      final goals = await api.getSavingsGoals();
      final subStats = await api.getSubscriptionStats();
      if (mounted) setState(() { _data = _SavingsData.fromJson(deposits, goals, subStats); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _data = _SavingsData.demo(); _loading = false; });
    }
  }

  Future<void> _addGoal() async {
    final ctrl = TextEditingController();
    final amtCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottom),
              decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Новая цель', style: dsH3()),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: kInk1)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: 'Название цели',
                      hintStyle: TextStyle(fontFamily: kFontText, color: kInk3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine, width: 1.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest900, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Целевая сумма ₽',
                      hintStyle: TextStyle(fontFamily: kFontText, color: kInk3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine, width: 1.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest900, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FpButton.gold(
                    full: true,
                    onPressed: () async {
                      final t = ctrl.text.trim();
                      final a = double.tryParse(amtCtrl.text.replaceAll(' ', '').replaceAll(',', '.'));
                      if (t.isEmpty || a == null || a <= 0) return;
                      Navigator.pop(ctx);
                      if (widget.demoMode) {
                        setState(() {
                          _demoGoals.add(_GoalItem(title: t, emoji: '🎯', current: 0, target: a));
                          _data = _SavingsData(
                            highDebt: _data?.highDebt ?? false,
                            goals: List.from(_demoGoals),
                            deposits: _data?.deposits ?? _SavingsData.demo().deposits,
                            subStats: _data?.subStats,
                          );
                        });
                      } else {
                        try {
                          await api.createSavingsGoal(title: t, targetAmount: a);
                          _load();
                        } catch (_) {}
                      }
                    },
                    child: const Text('Создать цель'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    amtCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: _loading
                  ? FpSkeleton(
                      child: ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                        children: [
                          FpBone(width: 150, height: 11),
                          const SizedBox(height: 16),
                          const FpBone(height: 180, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 160, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 120, radius: 24),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, isWide(context) ? 40 : 100),
                        children: [
                          FpFadeIn(delay: Duration.zero, child: FpOverline('Трекер накоплений')),
                          const SizedBox(height: 12),
                          if (_data!.highDebt) ...[
                            FpFadeIn(delay: const Duration(milliseconds: 60), child: _debtPriorityCard()),
                            const SizedBox(height: 16),
                          ],
                          FpFadeIn(delay: const Duration(milliseconds: 100), child: _goalsSection()),
                          const SizedBox(height: 16),
                          FpFadeIn(delay: const Duration(milliseconds: 180), child: _depositsSection()),
                          const SizedBox(height: 16),
                          FpFadeIn(delay: const Duration(milliseconds: 260), child: _subsCard()),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _debtPriorityCard() => FpCard(
    decoration: BoxDecoration(
      color: kRedBg,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: kRedRing, width: 2),
      boxShadow: shadowMd(),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_outlined, size: 22, color: kRed),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Сначала — дорогой долг', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: kInk1)),
          const SizedBox(height: 4),
          Text('Кредит под 20%+ «съедает» больше, чем даст вклад. Сначала гасим долг — потом копим.', style: dsSmall(color: kInk2)),
        ])),
      ],
    ),
  );

  Widget _goalsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FpOverline('Мои цели'),
            GestureDetector(
              onTap: _addGoal,
              child: Row(children: [
                const Icon(Icons.add, size: 16, color: kGreen),
                const SizedBox(width: 4),
                Text('Добавить', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: kGreen)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_data!.goals.isEmpty)
          FpCard(child: Text('Ещё нет целей. Добавь первую — Бади поможет накопить 🎯', style: dsSmall(color: kInk2)))
        else
          for (final g in _data!.goals) ...[_goalCard(g), const SizedBox(height: 12)],
      ],
    );
  }

  Widget _goalCard(_GoalItem g) {
    final pct = g.target > 0 ? (g.current / g.target).clamp(0.0, 1.0) : 0.0;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Text(g.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(g.title, style: dsH3()),
            ]),
            Text('${fmtRub(g.current)} / ${fmtRub(g.target)}', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: kInk3)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 14,
              backgroundColor: kGreenBg,
              valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
            ),
          ),
          if (g.monthlyRequired != null) ...[
            const SizedBox(height: 8),
            Text('При ${fmtRub(g.monthlyRequired!)} в месяц цель закроется к ${g.deadline ?? 'цели'}', style: dsSmall(color: kInk2)),
          ],
        ],
      ),
    );
  }

  Widget _depositsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FpOverline('Подобрано под твои цели'),
        const SizedBox(height: 10),
        if (_data!.deposits.isEmpty)
          FpCard(child: Text('Загружаем актуальные предложения…', style: dsSmall(color: kInk2)))
        else
          for (var i = 0; i < _data!.deposits.length; i++) ...[
            _depositCard(_data!.deposits[i], i == 0),
            if (i < _data!.deposits.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _depositCard(_DepositItem d, bool best) => FpCard(
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: best ? kGreen : kLine, width: best ? 2 : 1),
      boxShadow: shadowMd(),
    ),
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(d.bankName, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: kInk1)),
          if (best) ...[
            const SizedBox(width: 8),
            FpChip(child: const Text('лучшее'), bg: kGreenBg, color: kGreen),
          ],
        ]),
        const SizedBox(height: 3),
        Text(d.note, style: dsCaption(color: kInk3).copyWith(fontSize: 13)),
      ])),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${d.rate.toStringAsFixed(1)}%', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 24, color: kGreen, fontFeatures: const [FontFeature.tabularFigures()])),
        Text('годовых', style: dsCaption(color: kInk3)),
      ]),
    ]),
  );

  Widget _subsCard() {
    final s = _data!.subStats;
    if (s == null) return const SizedBox.shrink();
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FpOverline('Подписки и регулярные расходы'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _statNum('${s.activeCount}', 'активных')),
            Container(width: 1, height: 40, color: kLine),
            Expanded(child: _statNum(fmtRub(s.totalMonthly), 'в месяц')),
            Container(width: 1, height: 40, color: kLine),
            Expanded(child: _statNum('${s.suspiciousCount}', '⚠️ спорных')),
          ]),
        ],
      ),
    );
  }

  Widget _statNum(String val, String label) => Column(children: [
    Text(val, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 18, color: kInk1)),
    const SizedBox(height: 2),
    Text(label, style: dsCaption(color: kInk3)),
  ]);
}

// ============================================================
// Data models
// ============================================================

class _GoalItem {
  final String title, emoji;
  final double current, target;
  final double? monthlyRequired;
  final String? deadline;
  const _GoalItem({required this.title, required this.emoji, required this.current, required this.target, this.monthlyRequired, this.deadline});
}

class _DepositItem {
  final String bankName, note;
  final double rate;
  const _DepositItem({required this.bankName, required this.note, required this.rate});
}

class _SubStats {
  final int activeCount, suspiciousCount;
  final double totalMonthly;
  const _SubStats({required this.activeCount, required this.suspiciousCount, required this.totalMonthly});
}

class _SavingsData {
  final bool highDebt;
  final List<_GoalItem> goals;
  final List<_DepositItem> deposits;
  final _SubStats? subStats;
  const _SavingsData({required this.highDebt, required this.goals, required this.deposits, this.subStats});

  factory _SavingsData.demo() => const _SavingsData(
    highDebt: true,
    goals: [
      _GoalItem(title: 'Подушка безопасности', emoji: '🛡️', current: 62000, target: 150000, monthlyRequired: 12000, deadline: 'марту 2027'),
    ],
    deposits: [
      _DepositItem(bankName: 'Сбер · Вклад «Рост»', note: 'пополняемый · от 3 мес', rate: 18.5),
      _DepositItem(bankName: 'Накопительный счёт', note: 'снятие в любой момент', rate: 16.0),
      _DepositItem(bankName: 'Вклад «Полгода»', note: 'без пополнения · 6 мес', rate: 17.2),
    ],
    subStats: _SubStats(activeCount: 4, suspiciousCount: 1, totalMonthly: 1890),
  );

  factory _SavingsData.fromJson(List<dynamic> depositsJson, List<dynamic> goalsJson, Map<String, dynamic> subJson) {
    final goals = goalsJson.map<_GoalItem>((g) => _GoalItem(
      title: g['title'] as String? ?? 'Цель',
      emoji: g['emoji'] as String? ?? '🎯',
      current: (g['current_amount'] as num?)?.toDouble() ?? 0,
      target: (g['target_amount'] as num?)?.toDouble() ?? 0,
      monthlyRequired: (g['monthly_required'] as num?)?.toDouble(),
    )).toList();

    final deposits = depositsJson.take(3).map<_DepositItem>((d) {
      final cap = d['capitalization'] == true ? 'с капит.' : 'без капит.';
      final term = d['term_days_min'] != null ? '· от ${d['term_days_min']} дн.' : '';
      return _DepositItem(
        bankName: '${d['bank_name']} · ${d['product_name']}',
        note: '$cap $term'.trim(),
        rate: (d['rate_percent'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    final subStats = _SubStats(
      activeCount: (subJson['active_count'] as int?) ?? 0,
      suspiciousCount: (subJson['suspicious_count'] as int?) ?? 0,
      totalMonthly: (subJson['total_monthly'] as num?)?.toDouble() ?? 0,
    );

    return _SavingsData(
      highDebt: false,
      goals: goals,
      deposits: deposits.isEmpty ? _SavingsData.demo().deposits : deposits,
      subStats: subStats,
    );
  }
}
