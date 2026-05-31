import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'api_client.dart' as api;
import 'ds.dart';
import 'statement_import.dart';

class ForecastScreen extends StatefulWidget {
  final bool demoMode;
  const ForecastScreen({super.key, this.demoMode = false});
  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  _ForecastData? _data;
  bool _loading = true;
  StreamSubscription<void>? _mockSub;

  @override
  void initState() {
    super.initState();
    _load();
    _mockSub = api.onMockDataChanged.listen((_) { if (mounted) _load(); });
  }

  @override
  void dispose() {
    _mockSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await api.getForecast(demo: widget.demoMode);
      if (mounted) setState(() { _data = _ForecastData.fromJson(j); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _data = _ForecastData.demo(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
                          const FpBone(height: 200, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 160, radius: 24),
                          const SizedBox(height: 16),
                          const FpBone(height: 140, radius: 24),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                        children: [
                          FpFadeIn(delay: Duration.zero, child: FpOverline('Финансовый прогноз')),
                          const SizedBox(height: 12),
                          FpFadeIn(delay: const Duration(milliseconds: 80), child: _pdnDynamicsCard()),
                          const SizedBox(height: 16),
                          FpFadeIn(delay: const Duration(milliseconds: 160), child: _monthSummaryCard()),
                          const SizedBox(height: 16),
                          FpFadeIn(delay: const Duration(milliseconds: 240), child: _fixedExpensesCard()),
                          const SizedBox(height: 16),
                          FpFadeIn(
                            delay: const Duration(milliseconds: 300),
                            child: FpButton.secondary(
                          full: true,
                          onPressed: () async {
                            final file = await showStatementUploadSheet(context);
                            if (file == null || !mounted) return;
                            if (file.isMock) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Данные из выписки загружены.'), behavior: SnackBarBehavior.floating));
                              _load();
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка выписки…'), behavior: SnackBarBehavior.floating));
                            try {
                              await uploadStatement(file);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выписка отправлена.'), behavior: SnackBarBehavior.floating));
                              _load();
                            } catch (_) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить.'), behavior: SnackBarBehavior.floating));
                            }
                          },
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.upload_file_outlined, size: 18, color: kInk1),
                            SizedBox(width: 8),
                            Text('Загрузить выписку'),
                          ]),
                        ),
                      ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pdnDynamicsCard() {
    final d = _data!;
    final trend = d.trend;
    final trendColor = trend <= 0 ? kGreen : kRed;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FpOverline('Динамика ПДН'),
                  const SizedBox(height: 4),
                  Text('${d.currentPdn.round()}%', style: dsMetric(size: 36)),
                ],
              ),
              FpChip(
                bg: trend <= 0 ? kGreenBg : kRedBg,
                color: trendColor,
                child: Row(children: [
                  Icon(trend <= 0 ? Icons.trending_down : Icons.trending_up, size: 14, color: trendColor),
                  const SizedBox(width: 4),
                  Text('${trend > 0 ? '+' : ''}${trend.toStringAsFixed(1)}% за месяц'),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _barChart(d.months),
          const SizedBox(height: 12),
          Row(children: [
            _legend(false, 'факт'),
            const SizedBox(width: 14),
            _legend(true, 'прогноз'),
          ]),
        ],
      ),
    );
  }

  Widget _barChart(List<_MonthBar> months) {
    const maxH = 90.0;
    if (months.isEmpty) return const SizedBox(height: maxH + 20);
    final maxPdn = months.map((m) => m.pdn).reduce(math.max);
    final safeMax = maxPdn > 0 ? maxPdn : 1.0;
    return SizedBox(
      height: maxH + 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: months.map((m) {
          final z = zoneFor(m.pdn);
          final zc = zoneColors(z);
          final h = (m.pdn / safeMax * maxH).clamp(8.0, maxH);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  m.projected
                      ? Container(
                          height: h,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(4)),
                            border: Border.all(color: zc.ring, width: 2, style: BorderStyle.solid),
                          ),
                        )
                      : Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: zc.c.withValues(alpha: 0.85),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(4)),
                          ),
                        ),
                  const SizedBox(height: 6),
                  Text(m.label, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 10.5, color: kInk3)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legend(bool proj, String label) => Row(children: [
    proj
        ? Container(width: 10, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: kGreenRing, width: 2)))
        : Container(width: 10, height: 10, decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: dsCaption(color: kInk3).copyWith(fontSize: 12)),
  ]);

  Widget _monthSummaryCard() {
    final d = _data!;
    final rows = [
      _SummaryRow('Доход', d.income, kInk1, false),
      _SummaryRow('Обслуживание долга', -d.debt, kRed, false),
      _SummaryRow('Регулярные траты', -d.expenses, kInk2, false),
      _SummaryRow('Свободный остаток', d.free, d.free >= 0 ? kGreen : kRed, true),
    ];
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FpOverline('Картина месяца'),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(color: kLine, height: 1),
            _summaryRow(rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(_SummaryRow r) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(r.label, style: TextStyle(fontFamily: r.strong ? kFontDisplay : kFontText, fontWeight: r.strong ? FontWeight.w700 : FontWeight.w400, fontSize: 15, color: kInk1)),
      Text(
        r.amount >= 0 ? fmtRub(r.amount) : '−${fmtRub(r.amount.abs())}',
        style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: r.strong ? 19 : 16, color: r.color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    ]),
  );

  Widget _fixedExpensesCard() {
    final d = _data!;
    if (d.fixedExpenses.isEmpty) {
      return FpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FpOverline('Постоянные расходы'),
            const SizedBox(height: 12),
            Text('Загрузи выписку — Бади автоматически найдёт регулярные платежи.', style: dsSmall(color: kInk2)),
          ],
        ),
      );
    }
    final total = d.fixedExpenses.fold(0.0, (s, e) => s + e.amount);
    final pct = d.income > 0 ? total / d.income * 100 : 0.0;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FpOverline('Постоянные расходы'),
          const SizedBox(height: 12),
          for (var i = 0; i < d.fixedExpenses.length; i++) ...[
            if (i > 0) const Divider(color: kLine, height: 1),
            _fixedRow(d.fixedExpenses[i]),
          ],
          const Divider(color: kLine, height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Итого постоянных:', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 16, color: kInk1)),
              Text(fmtRub(total), style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 16, color: kInk1, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(height: 8),
          FpChip(
            bg: pct >= 50 ? kRedBg : pct >= 30 ? kYellowBg : kGreenBg,
            color: pct >= 50 ? kRed : pct >= 30 ? const Color(0xFF8A6200) : kGreen,
            child: Text('${pct.round()}% дохода'),
          ),
        ],
      ),
    );
  }

  Widget _fixedRow(_FixedExpense e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Text(e.emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(child: Text(e.name, style: dsBody(color: kInk1))),
      Text(fmtRub(e.amount), style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: kInk1)),
      const SizedBox(width: 8),
      FpChip(child: Text(e.period), bg: kSurface2, color: kInk3),
    ]),
  );
}

// ============================================================
// Data models
// ============================================================

class _MonthBar {
  final String label;
  final double pdn;
  final bool projected;
  const _MonthBar(this.label, this.pdn, {this.projected = false});
}

class _SummaryRow {
  final String label;
  final double amount;
  final Color color;
  final bool strong;
  const _SummaryRow(this.label, this.amount, this.color, this.strong);
}

class _FixedExpense {
  final String emoji, name, period;
  final double amount;
  const _FixedExpense(this.emoji, this.name, this.period, this.amount);
}

class _ForecastData {
  final double currentPdn, trend, income, debt, expenses, free;
  final List<_MonthBar> months;
  final List<_FixedExpense> fixedExpenses;

  const _ForecastData({
    required this.currentPdn, required this.trend, required this.income,
    required this.debt, required this.expenses, required this.free,
    required this.months, required this.fixedExpenses,
  });

  factory _ForecastData.demo() => const _ForecastData(
    currentPdn: 47.0, trend: -6.0,
    income: 92000, debt: 43264, expenses: 28600, free: 20136,
    months: [
      _MonthBar('Янв', 63), _MonthBar('Фев', 58), _MonthBar('Мар', 54),
      _MonthBar('Апр', 50), _MonthBar('Май', 47),
      _MonthBar('Июн', 43, projected: true), _MonthBar('Июл', 39, projected: true),
    ],
    fixedExpenses: [
      _FixedExpense('🏠', 'ЖКУ', 'ежемесячно', 4800),
      _FixedExpense('📱', 'МТС', 'ежемесячно', 650),
      _FixedExpense('🎬', 'Кинопоиск', 'ежемесячно', 399),
      _FixedExpense('🎵', 'Яндекс Плюс', 'ежемесячно', 299),
    ],
  );

  factory _ForecastData.fromJson(Map<String, dynamic> j) {
    final current = j['current'] as Map<String, dynamic>? ?? {};
    final income = (current['income'] as num?)?.toDouble() ?? 92000;
    final debt = (current['debt_payment'] as num?)?.toDouble() ?? 43264;
    final expenses = (current['expenses'] as num?)?.toDouble() ?? 28600;
    final free = (current['free'] as num?)?.toDouble() ?? 20136;
    final pdn = (current['pdn'] as num?)?.toDouble() ?? (income > 0 ? debt / income * 100 : 0.0);

    final hist = (j['history'] as List?) ?? [];
    final forecast = (j['forecast'] as List?) ?? [];
    final allMonths = <_MonthBar>[
      ...hist.map<_MonthBar>((m) => _MonthBar(m['month_label'] as String? ?? '?', (m['pdn'] as num?)?.toDouble() ?? 0)),
      ...forecast.map<_MonthBar>((m) => _MonthBar(m['month_label'] as String? ?? '?', (m['pdn'] as num?)?.toDouble() ?? 0, projected: true)),
    ];
    final months = allMonths.isEmpty ? _ForecastData.demo().months : allMonths;

    double trend = 0;
    if (hist.length >= 2) {
      final last = (hist.last['pdn'] as num?)?.toDouble() ?? pdn;
      final prev = (hist[hist.length - 2]['pdn'] as num?)?.toDouble() ?? pdn;
      trend = last - prev;
    }

    final rawFixed = (j['fixed_expenses'] as List?) ?? [];
    final fixed = rawFixed.map<_FixedExpense>((e) => _FixedExpense(
      e['emoji'] as String? ?? '📦',
      e['name'] as String? ?? '',
      e['period'] as String? ?? 'ежемесячно',
      (e['amount'] as num?)?.toDouble() ?? 0,
    )).toList();

    return _ForecastData(
      currentPdn: pdn, trend: trend, income: income, debt: debt,
      expenses: expenses, free: free, months: months, fixedExpenses: fixed,
    );
  }
}
