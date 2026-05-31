import 'dart:convert';
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
  PickedStatement(this.fileName, this.bytes);
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
// Mock: данные из реальной выписки «28 февраля 2026 – 31 мая 2026.xlsx»
// (Альфа-Банк, счёт 40817810508290297374, клиент Падеров А. С.)
// ---------------------------------------------------------------------------

const _kMockFileName = 'alfabank_28fev_31mai_2026.csv';
const _kMockDisplayName = '28 февраля 2026 – 31 мая 2026';

const _kMockCsvData = '''Дата,Описание,Сумма,Категория
13.03.2026,Зарплата (ООО Работодатель),30441.12,Доходы
27.03.2026,Зарплата аванс,13768.67,Доходы
14.04.2026,Зарплата (ООО Работодатель),30707.00,Доходы
29.04.2026,Зарплата аванс,12392.00,Доходы
14.05.2026,Зарплата (ООО Работодатель),20494.67,Доходы
29.05.2026,Зарплата (ООО Работодатель),48740.19,Доходы
04.03.2026,Пополнение через банкомат,37500.00,Прочие доходы
28.02.2026,Пятёрочка,-197.98,Еда и продукты
01.03.2026,Супермаркет,-1347.00,Еда и продукты
01.03.2026,Магнит,-299.63,Еда и продукты
08.03.2026,Магнит,-349.99,Еда и продукты
10.03.2026,Магнит,-206.98,Еда и продукты
10.03.2026,Светофор (дискаунтер),-155.50,Еда и продукты
17.03.2026,Магнит,-209.97,Еда и продукты
19.03.2026,Магнит,-432.36,Еда и продукты
25.03.2026,Магнит,-145.97,Еда и продукты
01.04.2026,Магнит,-599.99,Еда и продукты
05.04.2026,Магнит,-691.60,Еда и продукты
06.04.2026,Пятёрочка,-219.98,Еда и продукты
10.04.2026,Магнит,-1058.60,Еда и продукты
27.04.2026,"Чижик (X5 Digital)",-1951.16,Еда и продукты
05.05.2026,Горячая выпечка,-270.00,Еда и продукты
10.05.2026,Магнит,-109.99,Еда и продукты
17.05.2026,Магнит,-589.96,Еда и продукты
17.05.2026,Магнит,-266.98,Еда и продукты
02.03.2026,Пекарня,-270.00,Кафе и рестораны
08.03.2026,Tori Ramen,-1146.00,Кафе и рестораны
17.03.2026,Tori Ramen,-580.00,Кафе и рестораны
20.03.2026,Пекарня,-480.00,Кафе и рестораны
06.04.2026,Шаурма Тадж-Махал,-610.00,Кафе и рестораны
17.04.2026,Ресторан eatandsplit,-2813.00,Кафе и рестораны
29.04.2026,Tori Ramen,-1064.00,Кафе и рестораны
12.05.2026,Tori Ramen,-735.00,Кафе и рестораны
28.05.2026,Ресторан Галактика,-939.00,Кафе и рестораны
29.05.2026,Шаурма Тадж-Махал,-250.00,Кафе и рестораны
04.03.2026,Gold Apple Краснодар,-1321.27,Красота
16.03.2026,Стрижка Шоп,-450.00,Красота
23.03.2026,Летуаль,-1275.00,Красота
19.05.2026,Стрижка Шоп,-450.00,Красота
04.03.2026,Defile (магазин одежды),-8396.00,Одежда и обувь
11.03.2026,Ветаптека Центральная,-627.00,Животные
26.03.2026,Ветаптека,-219.00,Животные
06.05.2026,Ставропольская ВА (ветклиника),-276.00,Животные
29.05.2026,Ветаптека,-286.00,Животные
22.03.2026,Транспортная карта ЕБК,-55.00,Транспорт
22.03.2026,Транспортная карта ЕБК,-55.00,Транспорт
17.04.2026,Транспортная карта ЕБК,-55.00,Транспорт
11.03.2026,Магазин электроники,-500.00,Электроника
16.03.2026,МТС мобильная связь,-750.00,Телефон и интернет
16.03.2026,Интернет провайдер,-203.00,Телефон и интернет
20.04.2026,МТС мобильная связь,-203.00,Телефон и интернет
19.05.2026,МТС мобильная связь,-203.00,Телефон и интернет
04.04.2026,Леруа Мерлен,-2040.00,Товары для дома
29.03.2026,Ozon интернет-магазин,-1031.11,Покупки онлайн
22.04.2026,Ozon интернет-магазин,-1181.00,Покупки онлайн
31.03.2026,Ежемесячный платёж по кредиту,-5000.00,Кредиты и займы
''';

// ---------------------------------------------------------------------------
// Попап выбора файла выписки. Показывает кнопку «Загрузить файл» и список
// ранее использованных файлов.
// ---------------------------------------------------------------------------

Future<PickedStatement?> showStatementUploadSheet(BuildContext context) {
  return showModalBottomSheet<PickedStatement?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StatementUploadSheet(),
  );
}

class _StatementUploadSheet extends StatefulWidget {
  const _StatementUploadSheet();
  @override
  State<_StatementUploadSheet> createState() => _StatementUploadSheetState();
}

class _StatementUploadSheetState extends State<_StatementUploadSheet> {
  bool _picking = false;

  Future<void> _pickNew() async {
    setState(() => _picking = true);
    try {
      final file = await pickStatementFile();
      if (mounted) Navigator.pop(context, file);
    } catch (_) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  void _useMock() {
    Navigator.pop(
      context,
      PickedStatement(_kMockFileName, utf8.encode(_kMockCsvData)),
    );
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
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34, height: 34,
                          decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 18, color: kInk1),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    FpButton.gold(
                      full: true,
                      onPressed: _picking ? null : _pickNew,
                      child: _picking
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInkOnGold))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.upload_file_outlined, size: 18, color: kInkOnGold),
                              SizedBox(width: 8),
                              Text('Загрузить файл'),
                            ]),
                    ),
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
                    GestureDetector(
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
                            decoration: BoxDecoration(
                              color: kGreenBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.table_chart_outlined, color: kForest900, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _kMockDisplayName,
                                  style: const TextStyle(fontFamily: kFontDisplay, fontWeight: FontWeight.w700, fontSize: 14, color: kInk1),
                                ),
                                const SizedBox(height: 2),
                                Text('Альфа-Банк · 55 операций', style: dsCaption(color: kInk2)),
                                Text('март – май 2026', style: dsCaption(color: kInk3)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FpChip(
                            bg: kGoldTint,
                            color: kInkOnGold,
                            child: const Text('Использовать', style: TextStyle(fontSize: 12)),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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