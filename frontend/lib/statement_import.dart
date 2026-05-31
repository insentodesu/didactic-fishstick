import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart' as api;

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
// Отправка выписки на бэкенд.
//
// TODO(backend): реализовать загрузку файла на ваш API. Пример с http:
//
//   final req = http.MultipartRequest('POST', Uri.parse('$apiBase/statements'));
//   req.files.add(http.MultipartFile.fromBytes('file', file.bytes,
//       filename: file.fileName));
//   final resp = await req.send();
//   if (resp.statusCode != 200) throw Exception('upload failed');
//
// Сейчас — заглушка с искусственной задержкой, чтобы UI работал end-to-end.
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
        _error = 'Не удалось отправить файл. Проверьте соединение и попробуйте снова.';
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