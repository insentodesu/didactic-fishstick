import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart' as api;
import 'ds.dart';

// Russian month names in nominative and genitive cases
const _kMonthNom = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const _kMonthGen = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

String _monthLabel(DateTime d) => '${_kMonthNom[d.month - 1]} ${d.year}';
String _dayLabel(DateTime d) => '${d.day} ${_kMonthGen[d.month - 1]}';

class HistoryScreen extends StatefulWidget {
  final bool demoMode;
  const HistoryScreen({super.key, this.demoMode = false});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<api.TxRecord> _all = [];
  bool _loading = true;
  bool? _filter; // null=all, true=income, false=expense
  StreamSubscription<void>? _mockSub, _txSub;

  @override
  void initState() {
    super.initState();
    _load();
    _mockSub = api.onMockDataChanged.listen((_) { if (mounted) _load(); });
    _txSub = api.onTransactionChanged.listen((_) { if (mounted) _load(); });
  }

  @override
  void dispose() {
    _mockSub?.cancel();
    _txSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await api.getTransactionHistory(pageSize: 200, demo: widget.demoMode);
      if (mounted) setState(() { _all = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _all = []; _loading = false; });
    }
  }

  List<api.TxRecord> get _filtered {
    if (_filter == null) return _all;
    return _all.where((t) => t.isIncome == _filter).toList();
  }

  // Group by month label → list of TxRecord
  List<MapEntry<String, List<api.TxRecord>>> get _groups {
    final filtered = _filtered;
    final map = <String, List<api.TxRecord>>{};
    for (final t in filtered) {
      final key = _monthLabel(t.date);
      (map[key] ??= []).add(t);
    }
    return map.entries.toList();
  }

  double get _totalIncome => _filtered.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
  double get _totalExpense => _filtered.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : RefreshIndicator(
                    color: kGold,
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, wide ? 40 : 100),
                      children: [
                        _header(),
                        const SizedBox(height: 12),
                        _filterRow(),
                        const SizedBox(height: 12),
                        if (_all.isNotEmpty) ...[_summaryCard(), const SizedBox(height: 16)],
                        if (_filtered.isEmpty)
                          _emptyState()
                        else
                          for (final entry in _groups) ...[
                            _monthGroup(entry.key, entry.value),
                            const SizedBox(height: 16),
                          ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FpOverline('История операций'),
      const SizedBox(height: 2),
      Text('${_all.length} операций', style: dsSmall(color: kInk2)),
    ])),
  ]);

  Widget _filterRow() => Row(children: [
    _chip('Все', null),
    const SizedBox(width: 8),
    _chip('Доходы', true),
    const SizedBox(width: 8),
    _chip('Расходы', false),
  ]);

  Widget _chip(String label, bool? value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kForest900 : kSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kForest900 : kLine, width: 1.5),
        ),
        child: Text(label, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: active ? Colors.white : kInk2)),
      ),
    );
  }

  Widget _summaryCard() {
    return FpCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Expanded(child: _summaryCell(true, _totalIncome)),
        Container(width: 1, height: 40, color: kLine),
        Expanded(child: _summaryCell(false, _totalExpense)),
      ]),
    );
  }

  Widget _summaryCell(bool income, double amount) => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(income ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: income ? kGreen : kRed),
      const SizedBox(width: 4),
      Text(income ? 'Доходы' : 'Расходы', style: dsCaption(color: income ? kGreen : kRed)),
    ]),
    const SizedBox(height: 4),
    Text(fmtRub(amount), style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 18, color: income ? kGreen : kRed, fontFeatures: const [FontFeature.tabularFigures()])),
  ]);

  Widget _monthGroup(String monthLabel, List<api.TxRecord> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FpOverline(monthLabel),
      ),
      FpCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(color: kLine, height: 1),
            _txRow(items[i]),
          ],
        ]),
      ),
    ]);
  }

  Widget _txRow(api.TxRecord tx) {
    final color = tx.isIncome ? kGreen : kInk1;
    final sign = tx.isIncome ? '+' : '−';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: tx.isIncome ? kGreenBg : kSurface2,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(tx.categoryIcon, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx.name, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${tx.categoryName} · ${_dayLabel(tx.date)}', style: dsCaption(color: kInk3).copyWith(fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        Text('$sign${fmtRub(tx.amount)}', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(children: [
      const Text('📭', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text('Операций пока нет', style: dsH3(color: kInk2)),
      const SizedBox(height: 6),
      Text(_all.isEmpty ? 'Загрузи выписку или добавь операцию вручную' : 'Нет операций по выбранному фильтру', style: dsSmall(color: kInk3), textAlign: TextAlign.center),
    ]),
  );
}
