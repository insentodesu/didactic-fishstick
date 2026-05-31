import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class FinPetApp extends StatelessWidget {
  const FinPetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinPet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kCream,
        colorScheme: ColorScheme.fromSeed(seedColor: kForest900).copyWith(surface: kCream, onSurface: kInk1),
        useMaterial3: true,
        fontFamily: kFontText,
      ),
      home: const _RootGate(),
    );
  }
}

// ── Root gate ─────────────────────────────────────────────────────────────────

enum _Gate { loading, auth, onboarding, main }

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  _Gate _gate = _Gate.loading;
  bool _demoMode = false;

  @override
  void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    final token = await api.loadToken();
    if (token == null) { setState(() => _gate = _Gate.auth); return; }
    try {
      await api.getMe();
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('onboarding_done') ?? false;
      setState(() => _gate = done ? _Gate.main : _Gate.onboarding);
    } catch (e) {
      if (e is api.ApiException && e.statusCode == 401) {
        final ok = await api.tryRefreshTokens();
        if (ok) { await _check(); return; }
        await api.clearAllTokens();
      }
      setState(() => _gate = _Gate.auth);
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    setState(() => _gate = _Gate.main);
  }

  Future<void> _logout() async {
    await api.clearAllTokens();
    api.clearMockMode();
    setState(() { _demoMode = false; _gate = _Gate.auth; });
  }

  @override
  Widget build(BuildContext context) {
    switch (_gate) {
      case _Gate.loading:
        return const Scaffold(backgroundColor: kCream, body: Center(child: CircularProgressIndicator(color: kGold)));
      case _Gate.auth:
        return AuthScreen(
          onAuthenticated: _check,
          onDemo: () => setState(() { _demoMode = true; _gate = _Gate.main; }),
        );
      case _Gate.onboarding:
        return OnboardingFlow(onDone: _finishOnboarding);
      case _Gate.main:
        return MainShell(demoMode: _demoMode, onLogout: _logout);
    }
  }
}

// ── Auth Screen ───────────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  final VoidCallback onDemo;
  const AuthScreen({super.key, required this.onAuthenticated, required this.onDemo});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isRegister = false, _loading = false, _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_phoneCtrl, _passCtrl]) {
      c.addListener(() => setState(() => _error = null));
    }
  }

  @override
  void dispose() { _phoneCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  bool get _canSubmit {
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.length < 10 || _passCtrl.text.length < 6) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_isRegister) {
        await api.registerPhone(phone: _phoneCtrl.text.trim(), password: _passCtrl.text);
      } else {
        await api.loginPhone(phone: _phoneCtrl.text.trim(), password: _passCtrl.text);
        try {
          final me = await api.getMe();
          if (me['name'] != null) { final prefs = await SharedPreferences.getInstance(); await prefs.setString('user_name', me['name'] as String); }
        } catch (_) {}
      }
      if (mounted) widget.onAuthenticated();
    } on api.ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } catch (_) {
      if (mounted) setState(() => _error = 'Проверь подключение и попробуй снова');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              children: [
                Center(child: const FpPetAvatar(size: 90)),
                const SizedBox(height: 16),
                Center(child: Text('FinPet', style: dsH1())),
                Center(child: Text('Финансовый питомец', style: dsSmall(color: kInk2))),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    _toggle('Войти', !_isRegister, () => setState(() { _isRegister = false; _error = null; })),
                    _toggle('Регистрация', _isRegister, () => setState(() { _isRegister = true; _error = null; })),
                  ]),
                ),
                const SizedBox(height: 24),
                _lbl('Номер телефона'),
                _phoneField(),
                const SizedBox(height: 14),
                _lbl('Пароль'),
                _passField(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kRedRing)), child: Text(_error!, style: TextStyle(fontFamily: kFontText, fontSize: 13, color: kRed))),
                ],
                const SizedBox(height: 24),
                FpButton.gold(
                  full: true,
                  onPressed: (_canSubmit && !_loading) ? _submit : null,
                  child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInkOnGold)) : Text(_isRegister ? 'Создать аккаунт' : 'Войти'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: widget.onDemo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(999), border: Border.all(color: kLine)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('👁️', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Text('Демо — без регистрации', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: kInk2)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Center(child: Text('152-ФЗ · данные на серверах в России', textAlign: TextAlign.center, style: dsCaption(color: kInk3))),
              ],
            ),
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
        decoration: BoxDecoration(color: active ? kSurface : Colors.transparent, borderRadius: BorderRadius.circular(10), boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: active ? kInk1 : kInk3)),
      ),
    ),
  );

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: kInk2)));

  Widget _field(TextEditingController c, String hint, {TextCapitalization cap = TextCapitalization.none}) => TextField(
    controller: c, textCapitalization: cap,
    style: TextStyle(fontFamily: kFontDisplay, fontSize: 15, color: kInk1),
    decoration: _deco(hint),
  );

  Widget _phoneField() => TextField(
    controller: _phoneCtrl, keyboardType: TextInputType.phone,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\-\s()]'))],
    style: TextStyle(fontFamily: kFontDisplay, fontSize: 15, color: kInk1),
    decoration: _deco('+7 900 000-00-00'),
  );

  Widget _passField() => TextField(
    controller: _passCtrl, obscureText: _obscure,
    style: TextStyle(fontFamily: kFontDisplay, fontSize: 15, color: kInk1),
    decoration: _deco('Минимум 6 символов').copyWith(
      suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: kInk3, size: 20), onPressed: () => setState(() => _obscure = !_obscure)),
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(fontFamily: kFontText, color: kInk3, fontSize: 15),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine, width: 1.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest900, width: 1.5)),
  );
}

// ── Main Shell ────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  final bool demoMode;
  final VoidCallback? onLogout;
  const MainShell({super.key, this.demoMode = false, this.onLogout});
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
    final wide = isWide(context);
    final screens = [
      HomeScreen(demoMode: widget.demoMode, onSwitchTab: (i) => setState(() => _tab = i), onLogout: widget.onLogout),
      ForecastScreen(demoMode: widget.demoMode),
      PetScreen(onLesson: () => setState(() => _tab = 4)),
      const SavingsScreen(),
      const LessonsScreen(),
    ];
    if (wide) {
      return Scaffold(
        backgroundColor: kCream,
        body: Row(children: [
          _SideNav(current: _tab, tabs: _tabs, onTap: (i) => setState(() => _tab = i)),
          Expanded(child: IndexedStack(index: _tab, children: screens)),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: kCream,
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: _BottomBar(current: _tab, tabs: _tabs, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

class _TabItem { final IconData icon, activeIcon; final String label; const _TabItem(this.icon, this.activeIcon, this.label); }

class _BottomBar extends StatelessWidget {
  final int current; final List<_TabItem> tabs; final ValueChanged<int> onTap;
  const _BottomBar({required this.current, required this.tabs, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kLine))),
      child: SafeArea(top: false, child: SizedBox(height: 60, child: Row(children: [
        for (var i = 0; i < tabs.length; i++) Expanded(child: _BarItem(tab: tabs[i], active: i == current, onTap: () => onTap(i))),
      ]))),
    );
  }
}

class _BarItem extends StatelessWidget {
  final _TabItem tab; final bool active; final VoidCallback onTap;
  const _BarItem({super.key, required this.tab, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = active ? kForest900 : kInk3;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(active ? tab.activeIcon : tab.icon, color: color, size: 22),
      const SizedBox(height: 3),
      Text(tab.label, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 10, color: color)),
      if (active) ...[const SizedBox(height: 3), Container(width: 4, height: 4, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle))],
    ]));
  }
}

// ── Side Navigation (desktop) ─────────────────────────────────────────────────

class _SideNav extends StatelessWidget {
  final int current; final List<_TabItem> tabs; final ValueChanged<int> onTap;
  const _SideNav({super.key, required this.current, required this.tabs, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      decoration: const BoxDecoration(color: kSurface, border: Border(right: BorderSide(color: kLine))),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 18),
          const FpPetAvatar(size: 34),
          const SizedBox(height: 18),
          const Divider(color: kLine, height: 1),
          const SizedBox(height: 6),
          for (var i = 0; i < tabs.length; i++)
            _SideNavItem(tab: tabs[i], active: i == current, onTap: () => onTap(i)),
        ]),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final _TabItem tab; final bool active; final VoidCallback onTap;
  const _SideNavItem({super.key, required this.tab, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = active ? kForest900 : kInk3;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? kForest900.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(active ? tab.activeIcon : tab.icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(tab.label, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 10, color: color)),
          if (active) ...[const SizedBox(height: 3), Container(width: 4, height: 4, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle))],
        ]),
      ),
    );
  }
}

// ── HomeScreen ────────────────────────────────────────────────────────────────

class _TrafficLightData {
  final double pdn, monthlyIncome, monthlyDebt;
  final FinZone zone;
  final String advice;
  final List<_PlanStep> steps;
  const _TrafficLightData({required this.pdn, required this.zone, required this.advice, required this.steps, required this.monthlyIncome, required this.monthlyDebt});

  factory _TrafficLightData.demo() => const _TrafficLightData(
    pdn: 47.0, zone: FinZone.yellow, advice: '47% дохода уходит на кредиты. Давай снизим до 30%.',
    monthlyIncome: 92000, monthlyDebt: 43264,
    steps: [
      _PlanStep('Объединить 2 дорогих кредита', true), _PlanStep('Закрыть микрозайм 18 900 ₽', true),
      _PlanStep('Снизить лимит по карте', true), _PlanStep('Досрочно погасить 30 000 ₽', false, now: true),
      _PlanStep('Рефинансировать ипотеку', false), _PlanStep('Выйти в зелёную зону · ПДН 30%', false),
    ],
  );

  factory _TrafficLightData.fromJson(Map<String, dynamic> j) {
    final pdn = (j['pdn'] as num?)?.toDouble() ?? 47.0;
    final zone = j['zone'] == 'green' ? FinZone.green : j['zone'] == 'red' ? FinZone.red : FinZone.yellow;
    final rawSteps = j['plan_steps'] as List? ?? [];
    return _TrafficLightData(
      pdn: pdn, zone: zone, advice: j['advice'] as String? ?? '',
      monthlyIncome: (j['monthly_income'] as num?)?.toDouble() ?? 0,
      monthlyDebt: (j['monthly_debt'] as num?)?.toDouble() ?? 0,
      steps: rawSteps.map<_PlanStep>((s) => _PlanStep(s['title'] as String, s['done'] == true, now: s['now'] == true)).toList(),
    );
  }
}

class _PlanStep { final String title; final bool done, now; const _PlanStep(this.title, this.done, {this.now = false}); }

class HomeScreen extends StatefulWidget {
  final bool demoMode;
  final void Function(int) onSwitchTab;
  final VoidCallback? onLogout;
  const HomeScreen({super.key, required this.demoMode, required this.onSwitchTab, this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _TrafficLightData? _data;
  bool _loading = true;
  String _userName = '';
  bool _showDailyBanner = false, _showWeeklyBanner = false;
  StreamSubscription<void>? _mockSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _mockSub = api.onMockDataChanged.listen((_) { if (mounted) _loadAll(); });
  }

  @override
  void dispose() {
    _mockSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name') ?? '';
    final daily = await NotificationService.needsDailyReminder();
    final weekly = await NotificationService.needsWeeklyReminder();
    try {
      final j = await api.getTrafficLight(demo: widget.demoMode);
      if (mounted) setState(() { _data = _TrafficLightData.fromJson(j); _loading = false; _showDailyBanner = daily; _showWeeklyBanner = weekly; });
    } catch (_) {
      if (mounted) setState(() { _data = _TrafficLightData.demo(); _loading = false; _showDailyBanner = daily; _showWeeklyBanner = weekly; });
    }
  }

  Future<void> _importStatement() async {
    try {
      final file = await showStatementUploadSheet(context, demoMode: widget.demoMode);
      if (file == null || !mounted) return;

      if (file.isMock) {
        setState(() => _showWeeklyBanner = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Данные из выписки загружены.'), behavior: SnackBarBehavior.floating));
        _loadAll();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка выписки…'), behavior: SnackBarBehavior.floating));
      await uploadStatement(file);
      await NotificationService.markStatementUploaded();
      if (!mounted) return;
      setState(() => _showWeeklyBanner = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выписка отправлена. Данные обновятся через минуту.'), behavior: SnackBarBehavior.floating));
      await Future.delayed(const Duration(seconds: 6));
      _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить файл.'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final importBtn = FpButton.secondary(
      full: true,
      onPressed: _importStatement,
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.upload_file_outlined, size: 18, color: kInk1), SizedBox(width: 8), Text('Загрузить выписку')]),
    );
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : RefreshIndicator(
                    color: kGold, onRefresh: _loadAll,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, wide ? 40 : 100),
                      children: [
                        _topBar(), const SizedBox(height: 8),
                        FpOverline('Кредитный светофор'), const SizedBox(height: 12),
                        if (widget.demoMode) ...[_demoBanner(), const SizedBox(height: 12)],
                        if (_showDailyBanner) ...[_reminderBanner(daily: true), const SizedBox(height: 12)],
                        if (_showWeeklyBanner) ...[_reminderBanner(daily: false), const SizedBox(height: 12)],
                        if (wide) ...[
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _gaugeCard(), const SizedBox(height: 16), _petMiniCard(),
                            ])),
                            const SizedBox(width: 16),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _planCard(), const SizedBox(height: 16), importBtn,
                            ])),
                          ]),
                        ] else ...[
                          _gaugeCard(), const SizedBox(height: 16),
                          _planCard(), const SizedBox(height: 16),
                          _petMiniCard(), const SizedBox(height: 16),
                          importBtn,
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _demoBanner() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kGoldTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: kGoldDeep.withValues(alpha: 0.4))),
    child: Row(children: [
      const Text('👁️', style: TextStyle(fontSize: 16)), const SizedBox(width: 10),
      Expanded(child: Text('Демо-режим. Данные пробные.', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: kInkOnGold))),
      GestureDetector(onTap: widget.onLogout, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(8)), child: const Text('Войти', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: kInkOnGold)))),
    ]),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_userName.isNotEmpty ? 'Привет, $_userName 👋' : 'Привет 👋', style: dsSmall(color: kInk2)),
        const SizedBox(height: 2), Text('Финансы', style: dsH2()),
      ])),
      IconButton(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _NotifSettingsSheet()), icon: Icon(_showDailyBanner || _showWeeklyBanner ? Icons.notifications_active : Icons.notifications_outlined, color: _showDailyBanner || _showWeeklyBanner ? kRed : kForest900)),
      GestureDetector(
        onTap: () async {
          final result = await showModalBottomSheet<api.Tx>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _AddTxSheet());
          if (result != null) { await NotificationService.markExpenseLogged(); setState(() => _showDailyBanner = false); }
        },
        child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle), child: const Icon(Icons.add, color: kInkOnGold, size: 22)),
      ),
    ]),
  );

  Widget _gaugeCard() {
    final d = _data!; final zc = zoneColors(d.zone);
    return FpCard(
      decoration: BoxDecoration(color: zc.bg, borderRadius: BorderRadius.circular(24), border: Border.all(color: zc.ring, width: 2), boxShadow: shadowMd()),
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        FpRing(value: d.pdn, size: 120, stroke: 13, color: zc.c, track: Colors.white.withValues(alpha: 0.6), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.pdn.round()}%', style: dsMetric(size: 30, color: kInk1)),
          Text('ПДН', style: dsOverline(color: kInk3)),
        ])),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: zc.c, shape: BoxShape.circle)), const SizedBox(width: 6), Text(zc.label, style: dsOverline(color: zc.c == kYellow ? const Color(0xFF8A6200) : zc.c))]),
          const SizedBox(height: 6), Text(zoneTitle(d.zone), style: dsH3()),
          const SizedBox(height: 6), Text(d.advice.isNotEmpty ? d.advice : '${d.pdn.round()}% дохода уходит на кредиты.', style: dsSmall(color: kInk2)),
        ])),
      ]),
    );
  }

  Widget _planCard() {
    final steps = _data!.steps; final doneN = steps.where((s) => s.done).length;
    return FpCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [FpOverline('Путь в зелёную зону'), Text('шаг $doneN из ${steps.length}', style: dsOverline(color: kInk3))]),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++) ...[if (i > 0) const SizedBox(height: 10), _planStep(steps[i])],
      ]),
    );
  }

  Widget _planStep(_PlanStep s) => Opacity(
    opacity: s.done || s.now ? 1.0 : 0.5,
    child: Row(children: [
      Container(width: 26, height: 26, decoration: BoxDecoration(color: s.done ? kGreen : s.now ? kGold : kSurface2, shape: BoxShape.circle, border: (!s.done && !s.now) ? Border.all(color: kLineStrong, width: 1.5) : null), child: Icon(s.done ? Icons.check : Icons.arrow_upward, size: 14, color: s.done || s.now ? Colors.white : kInk3)),
      const SizedBox(width: 12),
      Expanded(child: Text(s.title, style: TextStyle(fontFamily: s.now ? kFontDisplay : kFontText, fontWeight: s.now ? FontWeight.w700 : FontWeight.w400, fontSize: 15, color: kInk1, decoration: s.done ? TextDecoration.lineThrough : null, decorationColor: kInk3))),
    ]),
  );

  Widget _petMiniCard() => FpCard(
    onTap: () => widget.onSwitchTab(2),
    child: Row(children: [
      const FpPetAvatar(size: 64), const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Бади ждёт урок', style: dsH3()), const SizedBox(height: 3), Text('2 минуты · покорми его 🦴', style: dsSmall(color: kInk2))])),
      FpButton.green(onPressed: () => widget.onSwitchTab(4), height: 36, child: const Text('Начать', style: TextStyle(fontSize: 13))),
    ]),
  );

  Widget _reminderBanner({required bool daily}) {
    final color = daily ? kRed : const Color(0xFF1565C0);
    final bg = daily ? kRedBg : const Color(0xFFE3F2FD);
    final ring = daily ? kRedRing : const Color(0xFF90CAF9);
    final title = daily ? 'Не забудь внести траты за сегодня' : 'Пора выгрузить выписку из банка';
    final sub = daily ? 'Питомец голоден — запиши расходы.' : 'Загрузи выписку — Бади проверит данные.';
    final label = daily ? 'Внести' : 'Загрузить';
    final action = daily ? () async {
      final result = await showModalBottomSheet<api.Tx>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _AddTxSheet());
      if (result != null) { await NotificationService.markExpenseLogged(); setState(() => _showDailyBanner = false); }
    } : _importStatement;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: ring, width: 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(daily ? Icons.edit_note : Icons.table_chart_outlined, size: 18, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          const SizedBox(height: 3), Text(sub, style: TextStyle(fontFamily: kFontText, fontSize: 12, color: color.withValues(alpha: 0.75), height: 1.4)),
          const SizedBox(height: 8),
          GestureDetector(onTap: action, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)), child: Text(label, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)))),
        ])),
        GestureDetector(onTap: () => setState(() { if (daily) _showDailyBanner = false; else _showWeeklyBanner = false; }), child: Icon(Icons.close, size: 16, color: color.withValues(alpha: 0.5))),
      ]),
    );
  }
}

// ── Add Transaction Sheet ─────────────────────────────────────────────────────

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
      final result = await api.scanReceiptQr(qr);
      if (!mounted) return;
      Navigator.pop(context);
      await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => _ReceiptSheet(data: result));
    } catch (e) {
      if (!mounted) return;
      final detail = e is api.ApiException ? e.detail : 'Попробуйте снова';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $detail'), behavior: SnackBarBehavior.floating, backgroundColor: kRed));
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
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Новая операция', style: dsH3()),
              GestureDetector(onTap: () => Navigator.pop(context), child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: kInk1))),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                _toggle('Расход', _isExpense, () => setState(() { _isExpense = true; _nameErr = null; _amtErr = null; })),
                _toggle('Доход', !_isExpense, () => setState(() { _isExpense = false; _nameErr = null; _amtErr = null; })),
              ]),
            ),
            const SizedBox(height: 16),
            if (_isExpense) ...[
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _scanReceipt, icon: const Icon(Icons.qr_code_scanner, size: 18), label: const Text('Сканировать QR чека'), style: OutlinedButton.styleFrom(foregroundColor: kGreen, side: const BorderSide(color: kGreen, width: 1.5), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
              const SizedBox(height: 14),
            ],
            _lbl('Описание'), _inp(_name, _isExpense ? 'Напр. Продукты' : 'Напр. Зарплата', error: _nameErr, onCh: () => setState(() => _nameErr = null)),
            const SizedBox(height: 14),
            _lbl('Сумма (₽)'), _inp(_amount, '0', number: true, error: _amtErr, onCh: () => setState(() => _amtErr = null)),
            if (_isExpense) ...[
              const SizedBox(height: 14), _lbl('Категория'), const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _cats.map((c) {
                final on = _cat == c;
                return GestureDetector(onTap: () => setState(() => _cat = c), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: on ? kGoldTint : kSurface, borderRadius: BorderRadius.circular(999), border: Border.all(color: on ? kGold : kLine, width: 1.5)), child: Text(c, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: on ? kInkOnGold : kInk2))));
              }).toList()),
            ],
            const SizedBox(height: 20),
            FpButton.gold(full: true, onPressed: _submit, child: const Text('Добавить операцию')),
          ]),
        ),
      ),
    );
  }

  Widget _toggle(String text, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: active ? kSurface : Colors.transparent, borderRadius: BorderRadius.circular(10), boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: active ? kInk1 : kInk3)),
    )),
  );

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 13, color: kInk2)));

  Widget _inp(TextEditingController c, String hint, {bool number = false, String? error, VoidCallback? onCh}) => TextField(
    controller: c, keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    onChanged: onCh != null ? (_) => onCh() : null,
    style: TextStyle(fontFamily: kFontDisplay, fontSize: 15, color: kInk1),
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(fontFamily: kFontText, color: kInk3, fontSize: 15),
      errorText: error, errorStyle: TextStyle(fontFamily: kFontText, fontSize: 12, color: kRed, height: 1.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error != null ? kRed : kLine, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: error != null ? kRed : kForest900, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kRed, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kRed, width: 1.5)),
    ),
  );
}

// ── Receipt Detail Sheet ──────────────────────────────────────────────────────

class _ReceiptSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReceiptSheet({required this.data});

  @override
  Widget build(BuildContext context) {
    final details = data['details'] as Map<String, dynamic>?;
    final parsed = data['parsed'] as Map<String, dynamic>? ?? {};
    final hasDetails = data['has_details'] == true;
    final sellerName = (details?['seller_name'] as String?)?.isNotEmpty == true ? details!['seller_name'] as String : 'Магазин';
    final total = hasDetails ? (details!['total_amount'] as num?)?.toDouble() ?? (parsed['amount'] as num?)?.toDouble() ?? 0.0 : (parsed['amount'] as num?)?.toDouble() ?? 0.0;
    final items = hasDetails ? (details!['items'] as List? ?? []) : <dynamic>[];
    final warning = data['warning'] as String?;
    final dateStr = parsed['purchase_date'] as String?;
    final dateLabel = dateStr != null && dateStr.length >= 10 ? dateStr.substring(0, 10) : 'сегодня';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FpOverline('Чек · $dateLabel'),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(sellerName, style: dsH3())),
                    Text(fmtRub(total), style: dsMetric(size: 28, color: kInk1)),
                  ]),
                  if (warning != null) ...[
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kYellowBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kYellowRing)), child: Row(children: [
                      const Icon(Icons.info_outline, size: 16, color: kYellow), const SizedBox(width: 8),
                      Expanded(child: Text('Список товаров недоступен без ключа ФНС. Сумма ${fmtRub(total)} сохранена.', style: TextStyle(fontFamily: kFontText, fontSize: 12, color: kInk2))),
                    ])),
                  ],
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FpOverline('Товары (${items.length})'),
                    const SizedBox(height: 8),
                    FpCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(color: kLine, height: 1),
                          _itemRow(items[i] as Map<String, dynamic>),
                        ],
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kGreenBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kGreenRing)), child: Row(children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: kGreen), const SizedBox(width: 8),
                    Expanded(child: Text(hasDetails ? 'Расход сохранён и категоризирован автоматически' : 'Расход ${fmtRub(total)} добавлен', style: TextStyle(fontFamily: kFontText, fontSize: 13, color: kGreen))),
                  ])),
                  const SizedBox(height: 16),
                  FpButton.green(full: true, onPressed: () => Navigator.pop(context), child: const Text('Готово')),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    final sum = (item['sum'] as num?)?.toDouble() ?? price * qty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: dsBody(color: kInk1)),
          if (qty != 1.0) Text('${qty % 1 == 0 ? qty.round() : qty} × ${fmtRub(price)}', style: dsCaption(color: kInk3).copyWith(fontSize: 12)),
        ])),
        Text(fmtRub(sum), style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1)),
      ]),
    );
  }
}

// ── Notification Settings ─────────────────────────────────────────────────────

class _NotifSettingsSheet extends StatefulWidget {
  const _NotifSettingsSheet();
  @override
  State<_NotifSettingsSheet> createState() => _NotifSettingsSheetState();
}

class _NotifSettingsSheetState extends State<_NotifSettingsSheet> {
  NotificationSettings _s = const NotificationSettings(dailyEnabled: false, weeklyEnabled: false, dailyHour: 21, dailyMin: 0);
  bool _granted = false, _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await NotificationService.loadSettings();
    setState(() { _s = s; _granted = NotificationService.isGranted; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Center(
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
                Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: _granted ? kGreenBg : kRedBg, borderRadius: BorderRadius.circular(12)), child: Row(children: [
                  Icon(_granted ? Icons.check_circle_outline : Icons.block_outlined, size: 18, color: _granted ? kGreen : kRed),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_granted ? 'Уведомления разрешены' : 'Не разрешены', style: TextStyle(fontFamily: kFontText, fontSize: 13, color: _granted ? kGreen : kRed))),
                  if (!_granted && !NotificationService.isDenied)
                    GestureDetector(onTap: () async { final ok = await NotificationService.requestPermission(); setState(() => _granted = ok); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(8)), child: const Text('Разрешить', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)))),
                ])),
                const SizedBox(height: 16),
                _row('Ежедневный напомин.', _s.dailyEnabled, (v) async {
                  if (v && !_granted) { final ok = await NotificationService.requestPermission(); setState(() => _granted = ok); if (!ok) return; }
                  final u = _s.copyWith(dailyEnabled: v); setState(() => _s = u); await NotificationService.saveSettings(u);
                }),
                const SizedBox(height: 10),
                _row('Еженедельный отчёт', _s.weeklyEnabled, (v) async {
                  if (v && !_granted) { final ok = await NotificationService.requestPermission(); setState(() => _granted = ok); if (!ok) return; }
                  final u = _s.copyWith(weeklyEnabled: v); setState(() => _s = u); await NotificationService.saveSettings(u);
                }),
              ]),
      ),
    ),
  );

  Widget _row(String title, bool value, ValueChanged<bool> onChanged) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: kCream, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1))), Switch(value: value, onChanged: onChanged, activeThumbColor: kGold, activeTrackColor: kGoldTint)]),
  );
}

// ── Onboarding Flow ───────────────────────────────────────────────────────────

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
  String? _creditOption;
  final _goals = <String>{};
  bool _loading = false;

  static const _goalOptions = [('debt', '💳', 'Погасить долги быстрее'), ('savings', '🐷', 'Начать копить'), ('awareness', '📊', 'Разобраться куда уходят деньги')];

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _incomeCtrl, _debtCtrl]) c.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _nameCtrl.dispose(); _incomeCtrl.dispose(); _debtCtrl.dispose(); super.dispose(); }

  bool get _hasCredits => _creditOption == 'some' || _creditOption == 'many';

  bool get _canNext {
    switch (_step) {
      case 1: return _nameCtrl.text.trim().isNotEmpty;
      case 2: return (double.tryParse(_incomeCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0) > 0;
      case 3:
        if (_creditOption == null) return false;
        if (_hasCredits) return (double.tryParse(_debtCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0) > 0;
        return true;
      case 4: return _goals.isNotEmpty;
      default: return true;
    }
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameCtrl.text.trim());
    final income = double.tryParse(_incomeCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    final debt = double.tryParse(_debtCtrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    try { await api.postOnboarding(monthlyIncome: income, hasCredits: _hasCredits, monthlyDebtPayment: debt, goals: _goals.toList()); } catch (_) {}
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kCream,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(padding: const EdgeInsets.fromLTRB(24, 32, 24, 32), child: _loading ? _loadingView() : _stepView()),
        ),
      ),
    ),
  );

  Widget _loadingView() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [const FpPetAvatar(size: 120), const SizedBox(height: 24), const CircularProgressIndicator(color: kGold), const SizedBox(height: 16), Text('Строю твой план…', style: dsH3())]);

  Widget _stepView() {
    switch (_step) {
      case 0: return _s0();
      case 1: return _s1();
      case 2: return _s2();
      case 3: return _s3();
      case 4: return _s4();
      default: return _s0();
    }
  }

  Widget _nav(int? back, String label, VoidCallback? onNext) => Row(children: [
    if (back != null) ...[FpButton.ghost(onPressed: () => setState(() => _step = back), child: const Text('Назад')), const SizedBox(width: 12)],
    Expanded(child: FpButton.gold(onPressed: _canNext ? onNext : null, child: Text(label))),
  ]);

  Widget _s0() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(), Center(child: const FpPetAvatar(size: 160)), const SizedBox(height: 32),
    Center(child: Text('Привет! Я Бади —\nтвой финансовый питомец', textAlign: TextAlign.center, style: dsH2())),
    const SizedBox(height: 12), Center(child: Text('Давай за 2 минуты разберёмся в твоих финансах', textAlign: TextAlign.center, style: dsSmall(color: kInk2))),
    const Spacer(), FpButton.gold(full: true, onPressed: () => setState(() => _step = 1), child: const Text('Начать')),
  ]);

  Widget _s1() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(), FpOverline('Знакомство'), const SizedBox(height: 12),
    Text('Как тебя зовут?', style: dsH2()), const SizedBox(height: 8),
    Text('Бади будет называть тебя по имени', style: dsSmall(color: kInk2)), const SizedBox(height: 24),
    TextField(controller: _nameCtrl, textCapitalization: TextCapitalization.words, style: dsH3(), decoration: InputDecoration(hintText: 'Например, Алексей', hintStyle: TextStyle(fontFamily: kFontDisplay, color: kInk3, fontSize: 21), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)))),
    const Spacer(), _nav(0, 'Далее', () => setState(() => _step = 2)),
  ]);

  Widget _s2() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(), FpOverline('Твой доход'), const SizedBox(height: 12),
    Text('Сколько ты зарабатываешь в месяц?', style: dsH2()), const SizedBox(height: 8),
    Text('Зарплата + подработки', style: dsSmall(color: kInk2)), const SizedBox(height: 24),
    TextField(controller: _incomeCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))], style: dsMetric(size: 36, color: kInk1), decoration: InputDecoration(suffixText: '₽/мес', suffixStyle: TextStyle(fontFamily: kFontDisplay, fontSize: 18, color: kInk3), hintText: '0', hintStyle: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w300, fontSize: 36, color: kInk3), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)))),
    const SizedBox(height: 16),
    Wrap(spacing: 8, children: ['30000', '50000', '80000', '120000'].map((v) => GestureDetector(onTap: () => setState(() => _incomeCtrl.text = v), child: FpChip(child: Text('${v.substring(0, v.length - 3)} ${v.substring(v.length - 3)}'), bg: kSurface2, color: kInk2, border: kLine))).toList()),
    const Spacer(), _nav(1, 'Далее', () => setState(() => _step = 3)),
  ]);

  Widget _s3() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(), FpOverline('Кредиты'), const SizedBox(height: 12),
    Text('Есть ли у тебя кредиты?', style: dsH2()), const SizedBox(height: 4),
    Text('Выберите один вариант', style: dsSmall(color: kInk3)), const SizedBox(height: 16),
    for (final (key, emoji, label) in [('none', '✅', 'Нет кредитов'), ('some', '💳', 'Есть 1–2 кредита'), ('many', '⚠️', 'Много кредитов')])
      GestureDetector(
        onTap: () => setState(() { _creditOption = key; if (key == 'none') _debtCtrl.clear(); }),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: _creditOption == key ? kGoldTint : kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _creditOption == key ? kGold : kLine, width: 1.5), boxShadow: shadowMd()), child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)), const SizedBox(width: 12), Text(label, style: dsBody(color: kInk1)),
          const Spacer(), if (_creditOption == key) const Icon(Icons.check_circle, color: kGold, size: 20),
        ])),
      ),
    if (_hasCredits) ...[
      const SizedBox(height: 4), Text('Сколько платишь в месяц?', style: dsSmall(color: kInk2)), const SizedBox(height: 8),
      TextField(controller: _debtCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))], style: dsH3(), decoration: InputDecoration(suffixText: '₽', hintText: '0', hintStyle: TextStyle(fontFamily: kFontDisplay, fontSize: 21, color: kInk3), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: kLine, width: 2)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kGold, width: 2)))),
    ],
    const Spacer(), _nav(2, 'Далее', () => setState(() => _step = 4)),
  ]);

  Widget _s4() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Spacer(), FpOverline('Цели'), const SizedBox(height: 12),
    Text('Что важнее сейчас?', style: dsH2()), const SizedBox(height: 8),
    Text('Можно выбрать несколько', style: dsSmall(color: kInk2)), const SizedBox(height: 16),
    for (final (key, emoji, label) in _goalOptions)
      GestureDetector(
        onTap: () => setState(() => _goals.contains(key) ? _goals.remove(key) : _goals.add(key)),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: _goals.contains(key) ? kGoldTint : kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _goals.contains(key) ? kGold : kLine, width: 1.5), boxShadow: shadowMd()), child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)), const SizedBox(width: 12), Text(label, style: dsBody(color: kInk1)),
          const Spacer(), if (_goals.contains(key)) const Icon(Icons.check_circle, color: kGold, size: 20),
        ])),
      ),
    const Spacer(), _nav(3, 'Построить план', _finish),
  ]);
}
