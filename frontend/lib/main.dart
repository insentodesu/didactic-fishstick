import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart' as api;
import 'ds.dart';
import 'forecast_screen.dart';
import 'lessons_screen.dart';
import 'notification_service.dart';
import 'pet_screen.dart';
import 'qr_scan.dart';
import 'savings_screen.dart';
import 'statement_import.dart';

void main() => runApp(const FinPetApp());

// ============================================================
// App
// ============================================================

class FinPetApp extends StatelessWidget {
  const FinPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinPet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kCream,
        colorScheme: ColorScheme.fromSeed(seedColor: kForest900, brightness: Brightness.light)
            .copyWith(surface: kCream, onSurface: kInk1),
        useMaterial3: true,
        fontFamily: kFontText,
      ),
      home: const _RootGate(),
    );
  }
}

// ============================================================
// Root gate — onboarding or main
// ============================================================

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _done = prefs.getBool('onboarding_done') ?? false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) {
      return const Scaffold(backgroundColor: kCream, body: Center(child: CircularProgressIndicator(color: kGold)));
    }
    if (!_done!) {
      return OnboardingFlow(onDone: () async {
        await _finish();
        if (!mounted) return;
        setState(() => _done = true);
      });
    }
    return const MainShell();
  }
}

// ============================================================
// Main shell — 5-tab nav
// ============================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  static const _tabs = [
    _TabItem(Icons.speed_outlined, Icons.speed, 'Светофор'),
    _TabItem(Icons.trending_up_outlined, Icons.trending_up, 'Прогноз'),
    _TabItem(Icons.pets_outlined, Icons.pets, 'Питомец'),
    _TabItem(Icons.savings_outlined, Icons.savings, 'Накопления'),
    _TabItem(Icons.school_outlined, Icons.school, 'Уроки'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onSwitchTab: (i) => setState(() => _tab = i)),
          const ForecastScreen(),
          PetScreen(onLesson: () => setState(() => _tab = 4)),
          const SavingsScreen(),
          const LessonsScreen(),
        ],
      ),
      bottomNavigationBar: _BottomBar(current: _tab, tabs: _tabs, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

class _TabItem {
  final IconData icon, activeIcon;
  final String label;
  const _TabItem(this.icon, this.activeIcon, this.label);
}

class _BottomBar extends StatelessWidget {
  final int current;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.current, required this.tabs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kLine, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(child: _BarItem(tab: tabs[i], active: i == current, onTap: () => onTap(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final _TabItem tab;
  final bool active;
  final VoidCallback onTap;
  const _BarItem({super.key, required this.tab, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? kForest900 : kInk3;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: active ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                active ? tab.activeIcon : tab.icon,
                key: ValueKey(active),
                color: color,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 10, color: color),
            child: Text(tab.label),
          ),
          const SizedBox(height: 3),
          AnimatedScale(
            scale: active ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HomeScreen — Кредитный светофор
// ============================================================

// ============================================================
// Home loading skeleton
// ============================================================

class _HomeLoadingSkeleton extends StatelessWidget {
  const _HomeLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return FpSkeleton(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FpBone(width: 130, height: 13),
                const SizedBox(height: 6),
                FpBone(width: 90, height: 24),
              ]),
            ),
            const FpBone(width: 40, height: 40, radius: 20),
          ]),
          const SizedBox(height: 20),
          FpBone(width: 140, height: 11),
          const SizedBox(height: 16),
          const FpBone(height: 158, radius: 24),
          const SizedBox(height: 16),
          const FpBone(height: 220, radius: 24),
          const SizedBox(height: 16),
          const FpBone(height: 96, radius: 24),
          const SizedBox(height: 16),
          const FpBone(height: 52, radius: 16),
        ],
      ),
    );
  }
}

class _TrafficLightData {
  final double pdn;
  final FinZone zone;
  final String advice;
  final List<_PlanStep> steps;
  final double monthlyIncome;
  final double monthlyDebt;

  const _TrafficLightData({
    required this.pdn,
    required this.zone,
    required this.advice,
    required this.steps,
    required this.monthlyIncome,
    required this.monthlyDebt,
  });

  factory _TrafficLightData.demo() => _TrafficLightData(
    pdn: 47.0,
    zone: FinZone.yellow,
    advice: '47% дохода уходит на кредиты. Давай снизим до 30%.',
    monthlyIncome: 92000,
    monthlyDebt: 43264,
    steps: [
      _PlanStep('Объединить 2 дорогих кредита', true),
      _PlanStep('Закрыть микрозайм 18 900 ₽', true),
      _PlanStep('Снизить лимит по карте', true),
      _PlanStep('Досрочно погасить 30 000 ₽', false, now: true),
      _PlanStep('Рефинансировать ипотеку', false),
      _PlanStep('Выйти в зелёную зону · ПДН 30%', false),
    ],
  );

  factory _TrafficLightData.fromJson(Map<String, dynamic> j) {
    final pdn = (j['pdn'] as num?)?.toDouble() ?? 47.0;
    final zone = j['zone'] == 'green' ? FinZone.green : j['zone'] == 'red' ? FinZone.red : FinZone.yellow;
    final rawSteps = j['plan_steps'] as List? ?? [];
    final steps = rawSteps.map<_PlanStep>((s) => _PlanStep(s['title'] as String, s['done'] == true, now: s['now'] == true)).toList();
    return _TrafficLightData(
      pdn: pdn,
      zone: zone,
      advice: j['advice'] as String? ?? '',
      steps: steps,
      monthlyIncome: (j['monthly_income'] as num?)?.toDouble() ?? 0,
      monthlyDebt: (j['monthly_debt'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _PlanStep {
  final String title;
  final bool done;
  final bool now;
  const _PlanStep(this.title, this.done, {this.now = false});
}

class HomeScreen extends StatefulWidget {
  final void Function(int) onSwitchTab;
  const HomeScreen({super.key, required this.onSwitchTab});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _TrafficLightData? _data;
  bool _loading = true;
  String _userName = '';
  bool _showDailyBanner = false;
  bool _showWeeklyBanner = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name') ?? '';
    final daily = await NotificationService.needsDailyReminder();
    final weekly = await NotificationService.needsWeeklyReminder();
    try {
      final j = await api.getTrafficLight(demo: true);
      if (mounted) setState(() { _data = _TrafficLightData.fromJson(j); _loading = false; _showDailyBanner = daily; _showWeeklyBanner = weekly; });
    } catch (_) {
      if (mounted) setState(() { _data = _TrafficLightData.demo(); _loading = false; _showDailyBanner = daily; _showWeeklyBanner = weekly; });
    }
  }

  Future<void> _importStatement() async {
    try {
      final file = await pickStatementFile();
      if (file == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка выписки…'), behavior: SnackBarBehavior.floating));
      await uploadStatement(file);
      await NotificationService.markStatementUploaded();
      if (!mounted) return;
      setState(() => _showWeeklyBanner = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выписка отправлена. Операции появятся после обработки.'), behavior: SnackBarBehavior.floating));
      _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить файл.'), behavior: SnackBarBehavior.floating));
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
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: child,
                ),
                child: _loading
                    ? const _HomeLoadingSkeleton()
                    : RefreshIndicator(
                        color: kGold,
                        onRefresh: _loadAll,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                          children: [
                            FpFadeIn(delay: Duration.zero, child: _topBar()),
                            const SizedBox(height: 8),
                            FpFadeIn(delay: const Duration(milliseconds: 60), child: FpOverline('Кредитный светофор')),
                            const SizedBox(height: 12),
                            if (_showDailyBanner) ...[
                              FpFadeIn(delay: const Duration(milliseconds: 80), child: _reminderBanner(daily: true)),
                              const SizedBox(height: 12),
                            ],
                            if (_showWeeklyBanner) ...[
                              FpFadeIn(delay: const Duration(milliseconds: 80), child: _reminderBanner(daily: false)),
                              const SizedBox(height: 12),
                            ],
                            FpFadeIn(delay: const Duration(milliseconds: 100), child: _gaugeCard()),
                            const SizedBox(height: 16),
                            FpFadeIn(delay: const Duration(milliseconds: 180), child: _planCard()),
                            const SizedBox(height: 16),
                            FpFadeIn(delay: const Duration(milliseconds: 260), child: _petMiniCard()),
                            const SizedBox(height: 16),
                            FpFadeIn(
                              delay: const Duration(milliseconds: 320),
                              child: FpButton.secondary(
                                full: true,
                                onPressed: _importStatement,
                                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.upload_file_outlined, size: 18, color: kInk1),
                                  SizedBox(width: 8),
                                  Text('Загрузить новую выписку'),
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_userName.isNotEmpty ? 'Привет, $_userName 👋' : 'Привет 👋', style: dsSmall(color: kInk2)),
                const SizedBox(height: 2),
                Text('Финансы', style: dsH2()),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _NotificationSettingsSheet()),
            icon: Icon(
              _showDailyBanner || _showWeeklyBanner ? Icons.notifications_active : Icons.notifications_outlined,
              color: _showDailyBanner || _showWeeklyBanner ? kRed : kForest900,
            ),
          ),
          GestureDetector(
            onTap: () async {
              final result = await showModalBottomSheet<api.Tx>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _AddTxSheet());
              if (result != null) {
                await NotificationService.markExpenseLogged();
                setState(() => _showDailyBanner = false);
              }
            },
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: kInkOnGold, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gaugeCard() {
    final d = _data!;
    final zc = zoneColors(d.zone);
    return FpCard(
      decoration: BoxDecoration(
        color: zc.bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: zc.ring, width: 2),
        boxShadow: shadowMd(),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FpRing(
            value: d.pdn,
            size: 120,
            stroke: 13,
            color: zc.c,
            track: Colors.white.withValues(alpha: 0.6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${d.pdn.round()}%', style: dsMetric(size: 30, color: kInk1)),
              Text('ПДН', style: dsOverline(color: kInk3)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: zc.c, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(zc.label, style: dsOverline(color: zc.c == kYellow ? const Color(0xFF8A6200) : zc.c)),
                ]),
                const SizedBox(height: 6),
                Text(zoneTitle(d.zone), style: dsH3()),
                const SizedBox(height: 6),
                Text(d.advice.isNotEmpty ? d.advice : '${d.pdn.round()}% дохода уходит на кредиты.', style: dsSmall(color: kInk2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard() {
    final steps = _data!.steps;
    final doneN = steps.where((s) => s.done).length;
    return FpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FpOverline('Путь в зелёную зону'),
              Text('шаг $doneN из ${steps.length}', style: dsOverline(color: kInk3)),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _planStep(steps[i]),
          ],
        ],
      ),
    );
  }

  Widget _planStep(_PlanStep s) {
    Color circleBg = s.done ? kGreen : s.now ? kGold : kSurface2;
    Color circleFg = s.done || s.now ? Colors.white : kInk3;
    return Opacity(
      opacity: s.done || s.now ? 1.0 : 0.5,
      child: Row(
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: circleBg,
              shape: BoxShape.circle,
              border: (!s.done && !s.now) ? Border.all(color: kLineStrong, width: 1.5) : null,
            ),
            child: Icon(s.done ? Icons.check : Icons.arrow_upward, size: 14, color: circleFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.title,
              style: TextStyle(
                fontFamily: s.now ? kFontDisplay : kFontText,
                fontWeight: s.now ? FontWeight.w700 : FontWeight.w400,
                fontSize: 15,
                color: kInk1,
                decoration: s.done ? TextDecoration.lineThrough : null,
                decorationColor: kInk3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _petMiniCard() {
    return FpCard(
      onTap: () => widget.onSwitchTab(2),
      child: Row(
        children: [
          const FpPetAvatar(size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Бади ждёт урок', style: dsH3()),
                const SizedBox(height: 3),
                Text('2 минуты · покорми его 🦴', style: dsSmall(color: kInk2)),
              ],
            ),
          ),
          FpButton.green(
            onPressed: () => widget.onSwitchTab(4),
            height: 36,
            child: const Text('Начать', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _reminderBanner({required bool daily}) {
    final color = daily ? kRed : const Color(0xFF1565C0);
    final bg = daily ? kRedBg : const Color(0xFFE3F2FD);
    final ring = daily ? kRedRing : const Color(0xFF90CAF9);
    final title = daily ? 'Не забудь внести траты за сегодня' : 'Пора выгрузить выписку из банка';
    final sub = daily ? 'Питомец голоден — запиши расходы, чтобы он не заболел.' : 'Бэкенд сверит данные и подтвердит точность учёта.';
    final label = daily ? 'Внести' : 'Загрузить';
    final action = daily
        ? () async {
            final result = await showModalBottomSheet<api.Tx>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _AddTxSheet());
            if (result != null) { await NotificationService.markExpenseLogged(); setState(() => _showDailyBanner = false); }
          }
        : _importStatement;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: ring, width: 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(daily ? Icons.edit_note : Icons.table_chart_outlined, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: color)),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(fontFamily: kFontText, fontSize: 12, color: color.withValues(alpha: 0.75), height: 1.4)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: action,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
              ),
            ),
          ]),
        ),
        GestureDetector(
          onTap: () => setState(() { if (daily) _showDailyBanner = false; else _showWeeklyBanner = false; }),
          child: Icon(Icons.close, size: 16, color: color.withValues(alpha: 0.5)),
        ),
      ]),
    );
  }
}

// ============================================================
// Add Transaction Sheet
// ============================================================

class _AddTxSheet extends StatefulWidget {
  const _AddTxSheet();
  @override
  State<_AddTxSheet> createState() => _AddTxSheetState();
}

class _AddTxSheetState extends State<_AddTxSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  bool _isExpense = true;
  String _cat = 'Еда';
  String? _nameErr, _amtErr;

  static const _cats = ['Еда', 'Транспорт', 'Покупки', 'Развлечения', 'Здоровье', 'ЖКУ', 'Подписки', 'Прочее'];

  @override
  void dispose() { _name.dispose(); _amount.dispose(); super.dispose(); }

  void _submit() {
    final parsed = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    final ne = _name.text.trim().isEmpty ? 'Введите описание' : null;
    final ae = _amount.text.trim().isEmpty ? 'Введите сумму' : parsed == null ? 'Некорректная сумма' : parsed <= 0 ? 'Сумма > 0' : null;
    if (ne != null || ae != null) { setState(() { _nameErr = ne; _amtErr = ae; }); return; }
    Navigator.pop(context, api.Tx(DateTime.now().millisecondsSinceEpoch, _name.text.trim(), _isExpense ? _cat : 'Доход', _isExpense ? -parsed!.abs() : parsed!.abs(), 'Сегодня'));
  }

  Future<void> _scanReceipt() async {
    final qr = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (qr == null || !mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка чека…'), behavior: SnackBarBehavior.floating));
      await uploadReceiptQr(qr);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Чек отправлен. Расход добавится после обработки.'), behavior: SnackBarBehavior.floating));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить чек.'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
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
                Text('Новая операция', style: dsH3()),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: kInk1)),
                ),
              ]),
              const SizedBox(height: 16),
              // Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _toggle('Расход', _isExpense, () => setState(() { _isExpense = true; _nameErr = null; _amtErr = null; })),
                  _toggle('Доход', !_isExpense, () => setState(() { _isExpense = false; _nameErr = null; _amtErr = null; })),
                ]),
              ),
              const SizedBox(height: 16),
              if (_isExpense) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanReceipt,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Сканировать QR чека'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kGreen,
                      side: const BorderSide(color: kGreen, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text('Описание', style: dsCaption(color: kInk2).copyWith(fontSize: 13, fontFamily: kFontDisplay, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _input(_name, _isExpense ? 'Напр. Продукты' : 'Напр. Зарплата', error: _nameErr, onChanged: () => setState(() => _nameErr = null)),
              const SizedBox(height: 14),
              Text('Сумма (₽)', style: dsCaption(color: kInk2).copyWith(fontSize: 13, fontFamily: kFontDisplay, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _input(_amount, '0', number: true, error: _amtErr, onChanged: () => setState(() => _amtErr = null)),
              if (_isExpense) ...[
                const SizedBox(height: 14),
                Text('Категория', style: dsCaption(color: kInk2).copyWith(fontSize: 13, fontFamily: kFontDisplay, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _cats.map((c) {
                    final on = _cat == c;
                    return GestureDetector(
                      onTap: () => setState(() => _cat = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: on ? kGoldTint : kSurface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: on ? kGold : kLine, width: 1.5),
                        ),
                        child: Text(c, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: on ? kInkOnGold : kInk2)),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),
              FpButton.gold(
                full: true,
                onPressed: _submit,
                child: const Text('Добавить операцию'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(String text, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? kSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: active ? kInk1 : kInk3)),
      ),
    ),
  );

  Widget _input(TextEditingController c, String hint, {bool number = false, String? error, VoidCallback? onChanged}) => TextField(
    controller: c,
    keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    onChanged: onChanged != null ? (_) => onChanged() : null,
    style: TextStyle(fontFamily: kFontDisplay, fontSize: 15, color: kInk1),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontFamily: kFontText, color: kInk3, fontSize: 15),
      errorText: error,
      errorStyle: TextStyle(fontFamily: kFontText, fontSize: 12, color: kRed, height: 1.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error != null ? kRed : kLine, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error != null ? kRed : kForest900, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kRed, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kRed, width: 1.5)),
    ),
  );
}

// ============================================================
// Notification settings sheet (minimal, kept from original)
// ============================================================

class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();
  @override
  State<_NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<_NotificationSettingsSheet> {
  NotificationSettings _s = const NotificationSettings(dailyEnabled: false, weeklyEnabled: false, dailyHour: 21, dailyMin: 0);
  bool _granted = false;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await NotificationService.loadSettings();
    setState(() { _s = s; _granted = NotificationService.isGranted; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: _loading ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: kGold)))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Уведомления', style: dsH3()),
                    GestureDetector(onTap: () => Navigator.pop(context), child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: kInk1))),
                  ]),
                  const SizedBox(height: 16),
                  _badge(),
                  const SizedBox(height: 16),
                  _row('Ежедневный напомин.', _s.dailyEnabled, (v) async {
                    if (v && !_granted) {
                      final ok = await NotificationService.requestPermission();
                      setState(() => _granted = ok);
                      if (!ok) return;
                    }
                    final u = _s.copyWith(dailyEnabled: v);
                    setState(() => _s = u);
                    await NotificationService.saveSettings(u);
                  }),
                  const SizedBox(height: 10),
                  _row('Еженедельный отчёт', _s.weeklyEnabled, (v) async {
                    if (v && !_granted) {
                      final ok = await NotificationService.requestPermission();
                      setState(() => _granted = ok);
                      if (!ok) return;
                    }
                    final u = _s.copyWith(weeklyEnabled: v);
                    setState(() => _s = u);
                    await NotificationService.saveSettings(u);
                  }),
                ]),
        ),
      ),
    );
  }

  Widget _badge() {
    final color = _granted ? kGreen : kRed;
    final bg = _granted ? kGreenBg : kRedBg;
    final text = _granted ? 'Уведомления разрешены' : 'Уведомления не разрешены';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(_granted ? Icons.check_circle_outline : Icons.block_outlined, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontFamily: kFontText, fontSize: 13, color: color))),
        if (!_granted && !NotificationService.isDenied)
          GestureDetector(
            onTap: () async { final ok = await NotificationService.requestPermission(); setState(() => _granted = ok); },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(8)), child: const Text('Разрешить', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white))),
          ),
      ]),
    );
  }

  Widget _row(String title, bool value, ValueChanged<bool> onChanged) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1))),
      Switch(value: value, onChanged: onChanged, activeThumbColor: kGold, activeTrackColor: kGoldTint),
    ]),
  );
}

// ============================================================
// Onboarding flow
// ============================================================

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingFlow({super.key, required this.onDone});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0;
  final _nameCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _debtCtrl = TextEditingController();
  bool _hasCredits = false;
  final _goals = <String>{};
  bool _loading = false;

  static const _goalOptions = [
    ('debt', '💳', 'Погасить долги быстрее'),
    ('savings', '🐷', 'Начать копить'),
    ('awareness', '📊', 'Разобраться куда уходят деньги'),
  ];

  @override
  void dispose() { _nameCtrl.dispose(); _incomeCtrl.dispose(); _debtCtrl.dispose(); super.dispose(); }

  Future<void> _finish() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameCtrl.text.trim());
    final income = double.tryParse(_incomeCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    final debt = double.tryParse(_debtCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    try {
      await api.postOnboarding(monthlyIncome: income, hasCredits: _hasCredits, monthlyDebtPayment: debt, goals: _goals.toList());
    } catch (_) {}
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: _loading ? _buildLoading() : _buildStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const FpPetAvatar(size: 120),
      const SizedBox(height: 24),
      const CircularProgressIndicator(color: kGold),
      const SizedBox(height: 16),
      Text('Строю твой план…', style: dsH3()),
    ],
  );

  Widget _buildStep() {
    switch (_step) {
      case 0: return _stepWelcome();
      case 1: return _stepName();
      case 2: return _stepIncome();
      case 3: return _stepCredits();
      case 4: return _stepGoals();
      default: return _stepWelcome();
    }
  }

  Widget _stepWelcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      Center(child: const FpPetAvatar(size: 160)),
      const SizedBox(height: 32),
      Center(child: Text('Привет! Я Бади —\nтвой финансовый питомец', textAlign: TextAlign.center, style: dsH2())),
      const SizedBox(height: 12),
      Center(child: Text('Давай за 2 минуты разберёмся в твоих финансах', textAlign: TextAlign.center, style: dsSmall(color: kInk2))),
      const Spacer(),
      FpButton.gold(full: true, onPressed: () => setState(() => _step = 1), child: const Text('Начать')),
    ],
  );

  Widget _stepName() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      FpOverline('Знакомство'),
      const SizedBox(height: 12),
      Text('Как тебя зовут?', style: dsH2()),
      const SizedBox(height: 8),
      Text('Бади будет называть тебя по имени', style: dsSmall(color: kInk2)),
      const SizedBox(height: 24),
      TextField(
        controller: _nameCtrl,
        textCapitalization: TextCapitalization.words,
        style: dsH3(),
        decoration: InputDecoration(
          hintText: 'Например, Алексей',
          hintStyle: TextStyle(fontFamily: kFontDisplay, color: kInk3, fontSize: 21),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)),
        ),
      ),
      const Spacer(),
      Row(children: [
        FpButton.ghost(onPressed: () => setState(() => _step = 0), child: const Text('Назад')),
        const SizedBox(width: 12),
        Expanded(child: FpButton.gold(onPressed: () => setState(() => _step = 2), child: const Text('Далее'))),
      ]),
    ],
  );

  Widget _stepIncome() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      FpOverline('Твой доход'),
      const SizedBox(height: 12),
      Text('Сколько ты зарабатываешь в месяц?', style: dsH2()),
      const SizedBox(height: 8),
      Text('Зарплата + подработки', style: dsSmall(color: kInk2)),
      const SizedBox(height: 24),
      TextField(
        controller: _incomeCtrl,
        keyboardType: TextInputType.number,
        style: dsMetric(size: 36, color: kInk1),
        decoration: InputDecoration(
          suffixText: '₽/мес',
          suffixStyle: TextStyle(fontFamily: kFontDisplay, fontSize: 18, color: kInk3),
          hintText: '0',
          hintStyle: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w300, fontSize: 36, color: kInk3),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: ['30 000', '50 000', '80 000', '120 000'].map((v) =>
        GestureDetector(
          onTap: () => setState(() => _incomeCtrl.text = v),
          child: FpChip(child: Text(v), bg: kSurface2, color: kInk2, border: kLine),
        )).toList()),
      const Spacer(),
      Row(children: [
        FpButton.ghost(onPressed: () => setState(() => _step = 1), child: const Text('Назад')),
        const SizedBox(width: 12),
        Expanded(child: FpButton.gold(onPressed: () => setState(() => _step = 3), child: const Text('Далее'))),
      ]),
    ],
  );

  Widget _stepCredits() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      FpOverline('Кредиты'),
      const SizedBox(height: 12),
      Text('Есть ли у тебя кредиты?', style: dsH2()),
      const SizedBox(height: 24),
      for (final (key, emoji, label) in [('none', '✅', 'Нет кредитов'), ('some', '💳', 'Есть 1–2 кредита'), ('many', '⚠️', 'Много кредитов')]) ...[
        GestureDetector(
          onTap: () => setState(() => _hasCredits = key != 'none'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (_hasCredits ? (key != 'none') : (key == 'none')) ? kGold : kLine, width: 1.5),
              boxShadow: shadowMd(),
            ),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Text(label, style: dsBody(color: kInk1)),
            ]),
          ),
        ),
      ],
      if (_hasCredits) ...[
        const SizedBox(height: 8),
        Text('Сколько платишь в месяц по кредитам?', style: dsSmall(color: kInk2)),
        const SizedBox(height: 8),
        TextField(
          controller: _debtCtrl,
          keyboardType: TextInputType.number,
          style: dsH3(),
          decoration: InputDecoration(
            suffixText: '₽',
            hintText: '0',
            hintStyle: TextStyle(fontFamily: kFontDisplay, fontSize: 21, color: kInk3),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)),
          ),
        ),
      ],
      const Spacer(),
      Row(children: [
        FpButton.ghost(onPressed: () => setState(() => _step = 2), child: const Text('Назад')),
        const SizedBox(width: 12),
        Expanded(child: FpButton.gold(onPressed: () => setState(() => _step = 4), child: const Text('Далее'))),
      ]),
    ],
  );

  Widget _stepGoals() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      FpOverline('Цели'),
      const SizedBox(height: 12),
      Text('Что важнее сейчас?', style: dsH2()),
      const SizedBox(height: 8),
      Text('Можно выбрать несколько', style: dsSmall(color: kInk2)),
      const SizedBox(height: 20),
      for (final (key, emoji, label) in _goalOptions) ...[
        GestureDetector(
          onTap: () => setState(() => _goals.contains(key) ? _goals.remove(key) : _goals.add(key)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: _goals.contains(key) ? kGoldTint : kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _goals.contains(key) ? kGold : kLine, width: 1.5),
              boxShadow: shadowMd(),
            ),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Text(label, style: dsBody(color: kInk1)),
              const Spacer(),
              if (_goals.contains(key)) const Icon(Icons.check_circle, color: kGold, size: 20),
            ]),
          ),
        ),
      ],
      const Spacer(),
      Row(children: [
        FpButton.ghost(onPressed: () => setState(() => _step = 3), child: const Text('Назад')),
        const SizedBox(width: 12),
        Expanded(child: FpButton.gold(onPressed: _finish, child: const Text('Построить план'))),
      ]),
    ],
  );
}
