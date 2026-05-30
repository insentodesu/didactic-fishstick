import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'statement_import.dart';
import 'qr_scan.dart';
import 'tamagotchi_screen.dart';
import 'notification_service.dart';

void main() => runApp(const FinanceApp());

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------
const _bg = Color(0xFFF4F1EC);
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF8A8678);
const _faint = Color(0xFFA09C8E);
const _green = Color(0xFF2A4D3E);
const _greenLite = Color(0xFF3D6B54);
const _incomeGreen = Color(0xFF2E7D4F);
const _expenseRed = Color(0xFFC0392B);

class Category {
  final String name;
  final IconData icon;
  final Color color;
  const Category(this.name, this.icon, this.color);
}

var categories = <String, Category>{
  'Еда': const Category('Еда', Icons.restaurant, Color(0xFFE8A87C)),
  'Покупки': const Category('Покупки', Icons.shopping_bag_outlined, Color(0xFFC38D9E)),
  'Транспорт': const Category('Транспорт', Icons.directions_car_outlined, Color(0xFF85C7C0)),
  'Жильё': const Category('Жильё', Icons.home_outlined, Color(0xFFA0A0D0)),
  'Услуги': const Category('Услуги', Icons.bolt_outlined, Color(0xFFE5C07B)),
  'Кофе': const Category('Кофе', Icons.coffee_outlined, Color(0xFFB5876A)),
  'Доход': const Category('Доход', Icons.work_outline, Color(0xFF7FB685)),
};

const _availableIcons = <IconData>[
  Icons.restaurant,
  Icons.shopping_bag_outlined,
  Icons.directions_car_outlined,
  Icons.home_outlined,
  Icons.bolt_outlined,
  Icons.coffee_outlined,
  Icons.sports_esports,
  Icons.local_hospital,
  Icons.school,
  Icons.flight,
  Icons.pets,
  Icons.fitness_center,
  Icons.movie,
  Icons.music_note,
  Icons.smartphone,
  Icons.savings,
  Icons.card_giftcard,
  Icons.directions_bike,
  Icons.spa,
  Icons.child_care,
];

const _availableColors = <Color>[
  Color(0xFFE8A87C),
  Color(0xFFC38D9E),
  Color(0xFF85C7C0),
  Color(0xFFA0A0D0),
  Color(0xFFE5C07B),
  Color(0xFFB5876A),
  Color(0xFF7FB685),
  Color(0xFFE06C75),
  Color(0xFF56B6C2),
  Color(0xFFD19A66),
  Color(0xFF98C379),
  Color(0xFFC678DD),
];

Future<void> _saveCustomCategory(Category cat) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('custom_categories');
  final list = existing != null ? (jsonDecode(existing) as List) : <dynamic>[];
  final iconIndex = _availableIcons.indexOf(cat.icon);
  list.add({
    'name': cat.name,
    'iconIndex': iconIndex >= 0 ? iconIndex : 0,
    'color': cat.color.toARGB32(),
  });
  await prefs.setString('custom_categories', jsonEncode(list));
}

class Tx {
  final int id;
  final String name;
  final String cat;
  final double amount; // negative = expense
  final String date;
  const Tx(this.id, this.name, this.cat, this.amount, this.date);
}

final seed = <Tx>[
  const Tx(1, 'Зарплата', 'Доход', 85000, '28 мая'),
  const Tx(2, 'Продукты', 'Еда', -3200, '28 мая'),
  const Tx(3, 'Кофейня', 'Кофе', -390, '27 мая'),
  const Tx(4, 'Такси', 'Транспорт', -680, '27 мая'),
  const Tx(5, 'Аренда', 'Жильё', -35000, '25 мая'),
  const Tx(6, 'Магазин одежды', 'Покупки', -4800, '24 мая'),
  const Tx(7, 'Электричество', 'Услуги', -2750, '23 мая'),
];

String fmt(double n) {
  final sign = n < 0 ? '-' : '';
  final v = n.abs().toStringAsFixed(2);
  final parts = v.split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
  return '$sign$intPart.${parts[1]} ₽';
}

// ---------------------------------------------------------------------------
class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Финансы',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: _bg,
        fontFamily: 'DMSans',
        useMaterial3: true,
      ),
      home: const _RootGate(),
    );
  }
}

// Решает, что показать при запуске: онбординг (первый раз) или главный экран.
class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  static const _prefKey = 'onboarding_done';
  bool? _seen; // null = ещё загружаем

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _seen = prefs.getBool(_prefKey) ?? false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    if (!_seen!) {
      return OnboardingScreen(
        onUploaded: () async {
          await _finish();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
        onSkip: () async {
          await _finish();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      );
    }
    return const HomeScreen();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<Tx> tx = List.of(seed);
  String _userName = '';
  bool _showAllTx = false;
  static const _txPreviewCount = 5;
  int _currentTab = 0;
  bool _showDailyBanner = false;
  bool _showWeeklyBanner = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadCustomCategories();
    _checkReminders();
  }

  Future<void> _checkReminders() async {
    final daily = await NotificationService.needsDailyReminder();
    final weekly = await NotificationService.needsWeeklyReminder();
    if (!mounted) return;
    setState(() {
      _showDailyBanner = daily;
      _showWeeklyBanner = weekly;
    });
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userName = prefs.getString('user_name') ?? '');
  }

  Future<void> _loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('custom_categories');
    if (json == null) return;
    final list = jsonDecode(json) as List;
    for (final item in list) {
      final name = item['name'] as String;
      final iconIndex = ((item['iconIndex'] as int?) ?? 0)
          .clamp(0, _availableIcons.length - 1);
      final colorValue = item['color'] as int;
      categories[name] = Category(
        name,
        _availableIcons[iconIndex],
        Color(colorValue),
      );
    }
    setState(() {});
  }

  double get income =>
      tx.where((t) => t.amount > 0).fold(0.0, (s, t) => s + t.amount);
  double get expense =>
      tx.where((t) => t.amount < 0).fold(0.0, (s, t) => s + t.amount);
  double get balance => income + expense;

  Future<void> _add() async {
    final result = await showModalBottomSheet<Tx>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddSheet(onCategoriesChanged: () => setState(() {})),
    );
    if (result != null) {
      setState(() {
        tx.insert(0, result);
        _showDailyBanner = false;
      });
      await NotificationService.markExpenseLogged();
    }
  }

  Future<void> _importStatement() async {
    try {
      final file = await pickStatementFile();
      if (file == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Отправка выписки на сервер…'),
        behavior: SnackBarBehavior.floating,
      ));
      await uploadStatement(file);
      await NotificationService.markStatementUploaded();
      if (!mounted) return;
      setState(() => _showWeeklyBanner = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Выписка отправлена. Операции появятся после обработки.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось отправить файл. Попробуйте снова.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _openNotificationSettings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NotificationSettingsSheet(),
    );
    if (mounted) _checkReminders();
  }

  List<Widget> _reminderBanners() {
    final banners = <Widget>[];
    if (_showDailyBanner) {
      banners.add(_reminderBanner(
        icon: Icons.edit_note,
        color: const Color(0xFFE65100),
        bg: const Color(0xFFFFF4E0),
        border: const Color(0xFFFFCC80),
        title: 'Не забудьте внести траты за сегодня',
        subtitle: 'Питомец голоден — запишите расходы, чтобы он не заболел.',
        onDismiss: () => setState(() => _showDailyBanner = false),
        onAction: _add,
        actionLabel: 'Внести',
      ));
      banners.add(const SizedBox(height: 12));
    }
    if (_showWeeklyBanner) {
      banners.add(_reminderBanner(
        icon: Icons.table_chart_outlined,
        color: const Color(0xFF1565C0),
        bg: const Color(0xFFE3F2FD),
        border: const Color(0xFF90CAF9),
        title: 'Пора выгрузить выписку из банка',
        subtitle: 'Бэкенд сверит данные и подтвердит точность вашего учёта.',
        onDismiss: () => setState(() => _showWeeklyBanner = false),
        onAction: _importStatement,
        actionLabel: 'Загрузить',
      ));
      banners.add(const SizedBox(height: 12));
    }
    return banners;
  }

  Widget _reminderBanner({
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
    required String title,
    required String subtitle,
    required VoidCallback onDismiss,
    required VoidCallback onAction,
    required String actionLabel,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: color.withValues(alpha: .75),
                          height: 1.4)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: onAction,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(actionLabel,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: color.withValues(alpha: .5)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton(
              onPressed: _add,
              backgroundColor: _green,
              elevation: 6,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        backgroundColor: Colors.white,
        selectedItemColor: _green,
        unselectedItemColor: _muted,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Финансы',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pets),
            activeIcon: Icon(Icons.pets),
            label: 'Питомец',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
                  children: [
                    _header(),
                    const SizedBox(height: 22),
                    ..._reminderBanners(),
                    _balanceCard(),
                    const SizedBox(height: 16),
                    _stats(),
                    const SizedBox(height: 22),
                    _txCard(),
                  ],
                ),
              ),
            ),
          ),
          const TamagotchiScreen(),
        ],
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _userName.isNotEmpty ? 'Привет, $_userName' : 'Привет',
                    style: const TextStyle(fontSize: 14, color: _muted)),
                const SizedBox(height: 2),
                const Text('Ваши финансы',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.5)),
              ],
            ),
          ),
          IconButton(
            onPressed: _openNotificationSettings,
            tooltip: 'Уведомления',
            icon: Icon(
              _showDailyBanner || _showWeeklyBanner
                  ? Icons.notifications_active
                  : Icons.notifications_outlined,
              color: _showDailyBanner || _showWeeklyBanner
                  ? const Color(0xFFE57373)
                  : _green,
            ),
          ),
          IconButton(
            onPressed: _importStatement,
            tooltip: 'Загрузить выписку',
            icon: const Icon(Icons.upload_file, color: _green),
          ),
          const SizedBox(width: 4),
          Container(
            width: 44,
            height: 44,
            decoration:
                const BoxDecoration(color: _ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
                _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _balanceCard() => Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green, _greenLite]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: _green.withValues(alpha: .35),
                blurRadius: 30,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Основной счёт',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
                const Text('Май 2026',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Текущий баланс',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(fmt(balance),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1)),
            const SizedBox(height: 14),
            const SizedBox(height: 40, child: _Sparkline()),
          ],
        ),
      );

  Widget _stats() => Row(
        children: [
          Expanded(
              child: _statCard('Доход', fmt(income), Icons.south_west,
                  const Color(0xFFE6F4EA), _incomeGreen)),
          const SizedBox(width: 12),
          Expanded(
              child: _statCard('Расход', fmt(expense), Icons.north_east,
                  const Color(0xFFFBEAEA), _expenseRed)),
        ],
      );

  Widget _statCard(String label, String value, IconData icon, Color bg,
          Color fg) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 12, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _ink)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _txCard() {
    final hasMore = tx.length > _txPreviewCount;
    final visible = _showAllTx ? tx : tx.take(_txPreviewCount).toList();
    final hidden = tx.length - _txPreviewCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Операции',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
              GestureDetector(
                onTap: hasMore
                    ? () => setState(() => _showAllTx = !_showAllTx)
                    : null,
                child: Text(
                  _showAllTx ? 'Свернуть' : 'Все',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasMore ? _green : _faint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...visible.map(_txRow),
          if (hasMore) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _showAllTx = !_showAllTx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  _showAllTx ? 'Свернуть' : 'Показать ещё $hidden',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _showAllTx ? _muted : _green),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _txRow(Tx t) {
    final c = categories[t.cat] ??
        Category(t.cat, Icons.label_outline, _faint);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _bg))),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: c.color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(c.icon, size: 18, color: c.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
                const SizedBox(height: 2),
                Text('${t.cat} · ${t.date}',
                    style: const TextStyle(fontSize: 12, color: _faint)),
              ],
            ),
          ),
          Text('${t.amount > 0 ? '+' : ''}${fmt(t.amount)}',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.amount > 0 ? _incomeGreen : _ink)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly sparkline (custom painter, no deps)
// ---------------------------------------------------------------------------
class _Sparkline extends StatelessWidget {
  const _Sparkline();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _SparkPainter());
}

class _SparkPainter extends CustomPainter {
  static const data = [38000.0, 34500, 31200, 42000, 67000, 55000, 38180];
  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.reduce((a, b) => a > b ? a : b);
    final minV = data.reduce((a, b) => a < b ? a : b);
    final dx = size.width / (data.length - 1);
    final pts = <Offset>[
      for (var i = 0; i < data.length; i++)
        Offset(
            i * dx,
            size.height -
                ((data[i] - minV) / (maxV - minV)) * (size.height - 6) -
                3),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) line.lineTo(p.dx, p.dy);

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: .4), Colors.white.withValues(alpha: 0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        line,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ---------------------------------------------------------------------------
// Add transaction bottom sheet
// ---------------------------------------------------------------------------
class AddSheet extends StatefulWidget {
  final VoidCallback? onCategoriesChanged;
  const AddSheet({super.key, this.onCategoriesChanged});
  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  bool isExpense = true;
  String cat = 'Еда';
  String? _nameError;
  String? _amountError;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    String? nameErr;
    String? amountErr;

    if (_name.text.trim().isEmpty) {
      nameErr = 'Введите описание операции';
    }
    if (_amount.text.trim().isEmpty) {
      amountErr = 'Введите сумму';
    } else if (parsed == null) {
      amountErr = 'Некорректная сумма — используйте цифры';
    } else if (parsed <= 0) {
      amountErr = 'Сумма должна быть больше нуля';
    }

    if (nameErr != null || amountErr != null) {
      setState(() {
        _nameError = nameErr;
        _amountError = amountErr;
      });
      return;
    }

    Navigator.pop(
      context,
      Tx(
        DateTime.now().millisecondsSinceEpoch,
        _name.text.trim(),
        isExpense ? cat : 'Доход',
        isExpense ? -parsed!.abs() : parsed!.abs(),
        'Сегодня',
      ),
    );
  }

  Future<void> _scanReceipt() async {
    final rawQr = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (rawQr == null || !mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Отправка данных чека на сервер…'),
        behavior: SnackBarBehavior.floating,
      ));
      await uploadReceiptQr(rawQr);
      if (!mounted) return;
      // Закрываем форму — расход появится после обработки на бэкенде.
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Чек отправлен. Расход добавится после обработки.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось отправить чек. Попробуйте снова.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _createCategory() async {
    final newCat = await showDialog<Category>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    if (newCat == null || !mounted) return;
    if (categories.containsKey(newCat.name)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Категория «${newCat.name}» уже существует'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    categories[newCat.name] = newCat;
    await _saveCustomCategory(newCat);
    setState(() => cat = newCat.name);
    widget.onCategoriesChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final expenseCats =
        categories.entries.where((e) => e.key != 'Доход').toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Новая операция',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                          color: _bg, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 20, color: _ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: _bg, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    _toggle('Расход', isExpense, () => setState(() {
                      isExpense = true;
                      _nameError = null;
                      _amountError = null;
                    })),
                    _toggle('Доход', !isExpense, () => setState(() {
                      isExpense = false;
                      _nameError = null;
                      _amountError = null;
                    })),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (isExpense) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _scanReceipt,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text('Сканировать QR чека'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: const BorderSide(color: _green, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _label('Описание'),
              _input(_name, isExpense ? 'Напр. Продукты' : 'Напр. Зарплата',
                  error: _nameError,
                  onChanged: () => setState(() => _nameError = null)),
              const SizedBox(height: 16),
              _label('Сумма (₽)'),
              _input(_amount, '0.00',
                  number: true,
                  error: _amountError,
                  onChanged: () => setState(() => _amountError = null)),
              if (isExpense) ...[
                const SizedBox(height: 16),
                _label('Категория'),
                const SizedBox(height: 2),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.4,
                  children: [
                    ...expenseCats.map((e) {
                      final on = cat == e.key;
                      return GestureDetector(
                        onTap: () => setState(() => cat = e.key),
                        child: Container(
                          decoration: BoxDecoration(
                            color: on
                                ? e.value.color.withValues(alpha: .1)
                                : Colors.white,
                            border: Border.all(
                                color: on ? e.value.color : const Color(0xFFEEEEEE),
                                width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(e.value.icon, size: 18, color: e.value.color),
                              const SizedBox(height: 5),
                              Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _ink)),
                            ],
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: _createCategory,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFFEEEEEE), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add, size: 18, color: _muted),
                            SizedBox(height: 5),
                            Text('Создать',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _muted)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Добавить операцию',
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
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
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .06),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(text,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: active ? _ink : _muted)),
          ),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, color: _muted, fontWeight: FontWeight.w500)),
      );

  Widget _input(
    TextEditingController c,
    String hint, {
    bool number = false,
    String? error,
    VoidCallback? onChanged,
  }) =>
      TextField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: onChanged != null ? (_) => onChanged() : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _faint),
          errorText: error,
          errorStyle:
              const TextStyle(fontSize: 12, color: _expenseRed, height: 1.3),
          errorMaxLines: 2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: error != null
                    ? _expenseRed
                    : const Color(0xFFEEEEEE),
                width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: error != null ? _expenseRed : _green, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _expenseRed, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _expenseRed, width: 1.5),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// New category dialog
// ---------------------------------------------------------------------------
class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();
  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _nameController = TextEditingController();
  IconData _selectedIcon = _availableIcons[0];
  Color _selectedColor = _availableColors[0];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, Category(name, _selectedIcon, _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Новая категория',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Название',
                hintStyle: const TextStyle(color: _faint),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            const SizedBox(height: 16),
            const Text('Иконка',
                style: TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableIcons.map((icon) {
                final on = icon == _selectedIcon;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = icon),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: on ? _selectedColor.withValues(alpha: .15) : _bg,
                      border: Border.all(
                        color: on ? _selectedColor : Colors.transparent,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        size: 20, color: on ? _selectedColor : _muted),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Цвет',
                style: TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableColors.map((color) {
                final on = color == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: on ? _ink : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: on
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: _muted)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notification settings bottom sheet
// ---------------------------------------------------------------------------
class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();
  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  NotificationSettings _settings = const NotificationSettings(
    dailyEnabled: false,
    weeklyEnabled: false,
    dailyHour: 21,
    dailyMin: 0,
  );
  bool _permGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await NotificationService.loadSettings();
    setState(() {
      _settings = s;
      _permGranted = NotificationService.isGranted;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService.requestPermission();
    setState(() => _permGranted = granted);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _settings.dailyHour, minute: _settings.dailyMin),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          timePickerTheme: const TimePickerThemeData(
            backgroundColor: Colors.white,
          ),
          colorScheme: const ColorScheme.light(primary: _green),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final updated =
        _settings.copyWith(dailyHour: picked.hour, dailyMin: picked.minute);
    setState(() => _settings = updated);
    await NotificationService.saveSettings(updated);
  }

  Future<void> _toggleDaily(bool val) async {
    if (val && !_permGranted) {
      final granted = await NotificationService.requestPermission();
      setState(() => _permGranted = granted);
      if (!granted) return;
    }
    final updated = _settings.copyWith(dailyEnabled: val);
    setState(() => _settings = updated);
    await NotificationService.saveSettings(updated);
  }

  Future<void> _toggleWeekly(bool val) async {
    if (val && !_permGranted) {
      final granted = await NotificationService.requestPermission();
      setState(() => _permGranted = granted);
      if (!granted) return;
    }
    final updated = _settings.copyWith(weeklyEnabled: val);
    setState(() => _settings = updated);
    await NotificationService.saveSettings(updated);
  }

  String _padTime(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 120,
                  child: Center(
                      child: CircularProgressIndicator(color: _green)))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Уведомления',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: _ink)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                                color: _bg, shape: BoxShape.circle),
                            child:
                                const Icon(Icons.close, size: 20, color: _ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Permission status
                    _permissionBadge(),
                    const SizedBox(height: 20),

                    // Daily reminder
                    _sectionLabel('Ежедневное напоминание'),
                    const SizedBox(height: 10),
                    _settingsRow(
                      icon: Icons.edit_note,
                      title: 'Внести траты за день',
                      subtitle:
                          'Напоминание, если расходы ещё не записаны сегодня',
                      value: _settings.dailyEnabled,
                      onChanged: _toggleDaily,
                    ),
                    if (_settings.dailyEnabled) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_outlined,
                                  size: 18, color: _muted),
                              const SizedBox(width: 10),
                              Text(
                                'Время напоминания: '
                                '${_padTime(_settings.dailyHour)}:'
                                '${_padTime(_settings.dailyMin)}',
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: _ink),
                              ),
                              const Spacer(),
                              const Icon(Icons.chevron_right,
                                  size: 18, color: _muted),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _previewPill(
                          '💰 Не забудьте внести траты',
                          'Питомец голоден — запишите вашу финансовую активность за сегодня!'),
                    ],
                    const SizedBox(height: 16),

                    // Weekly reminder
                    _sectionLabel('Еженедельный отчёт'),
                    const SizedBox(height: 10),
                    _settingsRow(
                      icon: Icons.table_chart_outlined,
                      title: 'Выгрузить выписку из банка',
                      subtitle:
                          'Каждое воскресенье — бэкенд сверяет и подтверждает данные',
                      value: _settings.weeklyEnabled,
                      onChanged: _toggleWeekly,
                    ),
                    if (_settings.weeklyEnabled) ...[
                      const SizedBox(height: 8),
                      _previewPill(
                          '📊 Время актуализировать данные',
                          'Выгрузите выписку из банка — проверка точности учёта.'),
                    ],
                    const SizedBox(height: 20),

                    // Test buttons
                    if (_permGranted) ...[
                      const Divider(color: _bg),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _testBtn(
                            'Тест: ежедневное',
                            NotificationService.showDailyReminder,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _testBtn(
                            'Тест: еженедельное',
                            NotificationService.showWeeklyReminder,
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _permissionBadge() {
    final granted = _permGranted;
    final denied = NotificationService.isDenied;
    final color =
        granted ? const Color(0xFF4CAF50) : const Color(0xFFE57373);
    final bg =
        granted ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final text = granted
        ? 'Уведомления разрешены браузером'
        : denied
            ? 'Уведомления запрещены — разрешите в настройках браузера'
            : 'Уведомления ещё не разрешены';
    final icon = granted ? Icons.check_circle_outline : Icons.block_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 12.5, color: color))),
          if (!granted && !denied) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _requestPermission,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Разрешить',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _muted,
          letterSpacing: 0.4));

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: value ? _green.withValues(alpha: .12) : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18, color: value ? _green : _muted),
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
                      style: const TextStyle(
                          fontSize: 11.5, color: _muted, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: _green,
              activeTrackColor: _green.withValues(alpha: .4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );

  Widget _previewPill(String title, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.notifications, size: 16, color: _green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 11, color: _muted, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _testBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _green)),
        ),
      );
}
