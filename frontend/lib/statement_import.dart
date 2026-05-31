import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart' as api;
import 'ds.dart';

// Локальные токены (Dart не делит private-символы между файлами).
const _green = Color(0xFF2A4D3E);
const _greenLite = Color(0xFF3D6B54);
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF8A8678);
const _bg = Color(0xFFF4F1EC);

// ---------------------------------------------------------------------------
// Выбранный файл выписки. Парсинг НЕ выполняется на клиенте — байты и имя
// файла отправляются на бэкенд для дальнейшей обработки.
// ---------------------------------------------------------------------------
class PickedStatement {
  final String fileName;
  final List<int> bytes;
  final bool isMock;
  PickedStatement(this.fileName, this.bytes, {this.isMock = false});
}

// Открывает picker и возвращает выбранный файл (без разбора содержимого).
// null — пользователь отменил выбор.
Future<PickedStatement?> pickStatementFile() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf'],
    withData: true, // важно для web — байты приходят в памяти
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final bytes = f.bytes;
  if (bytes == null) return null;
  return PickedStatement(f.name, bytes);
}

// ---------------------------------------------------------------------------
// Mock: аналитика, рассчитанная из реальной выписки Альфа-Банка
// ---------------------------------------------------------------------------

const _kMockDisplayName = '28 февраля 2026 – 31 мая 2026';

final _kMockTrafficLight = <String, dynamic>{
  'pdn': 11.3,
  'zone': 'green',
  'monthly_income': 44210.0,
  'monthly_debt': 5000.0,
  'advice': 'ПДН 11% — отличный результат! Вы направляете менее 15% дохода на кредиты. Есть резерв для накоплений и инвестиций.',
  'plan_steps': <Map<String, dynamic>>[
    {'title': 'Загрузить банковскую выписку', 'done': true},
    {'title': 'ПДН < 30% — стабильная зелёная зона', 'done': true},
    {'title': 'Создать подушку безопасности (3 месяца расходов)', 'done': false, 'now': true},
    {'title': 'Открыть накопительный вклад', 'done': false},
    {'title': 'Начать инвестировать часть дохода', 'done': false},
    {'title': 'Финансовая независимость · ПДН 0%', 'done': false},
  ],
};

final _kMockForecast = <String, dynamic>{
  'current': <String, dynamic>{
    'income': 44210.0,
    'debt_payment': 5000.0,
    'expenses': 15200.0,
    'free': 24010.0,
    'pdn': 11.3,
  },
  'history': <Map<String, dynamic>>[
    {'month': '2026-03', 'month_label': 'Мар', 'income': 44210, 'debt_payment': 5000, 'pdn': 11.3},
    {'month': '2026-04', 'month_label': 'Апр', 'income': 43099, 'debt_payment': 5000, 'pdn': 11.6},
    {'month': '2026-05', 'month_label': 'Май', 'income': 69235, 'debt_payment': 5000, 'pdn': 7.2},
  ],
  'forecast': <Map<String, dynamic>>[
    {'month': '2026-06', 'month_label': 'Июн', 'pdn': 7.0, 'projected': true},
    {'month': '2026-07', 'month_label': 'Июл', 'pdn': 6.5, 'projected': true},
  ],
  'fixed_expenses': <Map<String, dynamic>>[
    {'emoji': '📱', 'name': 'МТС (мобильная связь)', 'period': 'ежемесячно', 'amount': 203},
    {'emoji': '🌐', 'name': 'Интернет провайдер', 'period': 'ежемесячно', 'amount': 203},
    {'emoji': '💳', 'name': 'Кредитный платёж', 'period': 'ежемесячно', 'amount': 5000},
  ],
};

// ---------------------------------------------------------------------------
// Попап выбора файла выписки. Показывает кнопку «Загрузить файл» и список
// ранее использованных файлов.
// ---------------------------------------------------------------------------

Future<PickedStatement?> showStatementUploadSheet(BuildContext context, {bool demoMode = false}) {
  return showModalBottomSheet<PickedStatement?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StatementUploadSheet(demoMode: demoMode),
  );
}

class _StatementUploadSheet extends StatefulWidget {
  final bool demoMode;
  const _StatementUploadSheet({this.demoMode = false});
  @override
  State<_StatementUploadSheet> createState() => _StatementUploadSheetState();
}

class _StatementUploadSheetState extends State<_StatementUploadSheet> {
  bool _picking = false;
  bool _processingMock = false;
  bool _demoLoading = false;
  bool _demoError = false;

  bool get _busy => _picking || _processingMock || _demoLoading;

  Future<void> _pickNew() async {
    _showUploadLimitDenied();
  }

  Future<void> _useMock() async {
    setState(() => _processingMock = true);
    api.setMockAnalytics(
      trafficLight: _kMockTrafficLight,
      forecast: _kMockForecast,
    );
    try {
      await api.uploadDemoStatement();
    } catch (_) {}
    if (mounted) Navigator.pop(context, PickedStatement('', [], isMock: true));
  }

  Future<void> _showUploadLimitDenied() async {
    setState(() { _demoLoading = true; _demoError = false; });
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() { _demoLoading = false; _demoError = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: const BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Text('Загрузить выписку', style: dsH3()),
                      const Spacer(),
                      GestureDetector(
                        onTap: _busy ? null : () => Navigator.pop(context),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(color: kCream, shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 18, color: _busy ? kInk3 : kInk1),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    FpButton.gold(
                      full: true,
                      onPressed: _busy ? null : _pickNew,
                      child: (_picking || _demoLoading)
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInkOnGold))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.upload_file_outlined, size: 18, color: kInkOnGold),
                              SizedBox(width: 8),
                              Text('Загрузить файл'),
                            ]),
                    ),
                    if (_demoLoading || _demoError) ...[
                      const SizedBox(height: 12),
                      _demoLoading ? _buildDemoLoadingCard() : _buildDemoErrorCard(),
                    ],
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider(color: kLine)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('или', style: dsCaption(color: kInk3)),
                      ),
                      const Expanded(child: Divider(color: kLine)),
                    ]),
                    const SizedBox(height: 16),
                    FpOverline('Недавние файлы'),
                    const SizedBox(height: 10),
                    _processingMock ? _buildProcessingCard() : _buildFileCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kGoldTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGoldDeep.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: kGold),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Обрабатываем выписку…', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1)),
              const SizedBox(height: 1),
              Text(_kMockDisplayName, style: dsCaption(color: kInk2)),
            ])),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 5),
            builder: (context, value, _) {
              final msg = value < 0.3
                  ? 'Читаем транзакции…'
                  : value < 0.65
                      ? 'Категоризируем операции ИИ…'
                      : 'Строим финансовый прогноз…';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: kGoldSoft,
                    valueColor: const AlwaysStoppedAnimation<Color>(kGold),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(msg, style: dsCaption(color: kInk2)),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDemoLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kGoldTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGoldDeep.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: kGold)),
            const SizedBox(width: 12),
            Expanded(child: Text('Проверяем доступность загрузки…', style: TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1))),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 3),
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: kGoldSoft,
                valueColor: const AlwaysStoppedAnimation<Color>(kGold),
                minHeight: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kRedBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kRedRing, width: 1.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: kRed, size: 22),
        const SizedBox(width: 12),
        const Expanded(child: Text(
          'Ранее вы уже загружали выписку, эту операцию можно проводить только раз в 3 дня',
          style: TextStyle(fontFamily: kFontText, fontSize: 14, color: kRed, height: 1.4),
        )),
      ]),
    );
  }

  Widget _buildFileCard() {
    return GestureDetector(
      onTap: _useMock,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLine, width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: kGreenBg, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.table_chart_outlined, color: kForest900, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_kMockDisplayName, style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1)),
            const SizedBox(height: 2),
            Text('Альфа-Банк · 55 операций', style: dsCaption(color: kInk2)),
            Text('март – май 2026', style: dsCaption(color: kInk3)),
          ])),
          const SizedBox(width: 8),
          FpChip(bg: kGoldTint, color: kInkOnGold, child: const Text('Использовать', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Отправка выписки на бэкенд.
// ---------------------------------------------------------------------------
Future<void> uploadStatement(PickedStatement file) async {
  await api.uploadStatement(Uint8List.fromList(file.bytes), file.fileName);
}

// ---------------------------------------------------------------------------
// Экран онбординга (первый запуск)
// ---------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  // Вызывается после успешной отправки файла на бэкенд.
  final VoidCallback onUploaded;
  final VoidCallback onSkip;
  const OnboardingScreen({super.key, required this.onUploaded, required this.onSkip});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;
  String? _error;
  final _nameController = TextEditingController();

  static const _nameKey = 'user_name';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<void> _upload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final file = await pickStatementFile();
      if (!mounted) return;
      if (file == null) {
        setState(() => _loading = false);
        return;
      }
      await Future.wait([uploadStatement(file), _saveName()]);
      if (!mounted) return;
      widget.onUploaded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is api.ApiException
            ? e.detail
            : 'Не удалось отправить файл. Проверьте соединение и попробуйте снова.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_green, _greenLite]),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 24),
                  const Text('Добро пожаловать',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  const Text(
                    'Чтобы начать, загрузите банковскую выписку в Excel за последние 3 месяца. '
                    'Мы обработаем доходы и расходы и разнесём их по категориям.',
                    style: TextStyle(fontSize: 15, color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  _hintRow(Icons.table_chart_outlined, 'Форматы .xlsx, .xls, .csv и .pdf'),
                  const SizedBox(height: 12),
                  _hintRow(Icons.cloud_upload_outlined, 'Файл обрабатывается на сервере'),
                  const SizedBox(height: 12),
                  _hintRow(Icons.auto_awesome_outlined, 'Категории определяются автоматически'),
                  const SizedBox(height: 28),
                  const Text('Как вас зовут?',
                      style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Например, Алексей',
                      hintStyle: const TextStyle(color: _muted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFEEEEEE), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _green, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFBEAEA),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFC0392B), fontSize: 13.5)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _upload,
                      icon: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.upload_file, size: 20),
                      label: Text(_loading ? 'Отправка…' : 'Загрузить выписку'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : () async {
                        await _saveName();
                        widget.onSkip();
                      },
                      child: const Text('Пропустить и начать с нуля',
                          style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 18, color: _green),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: _ink))),
        ],
      );
}