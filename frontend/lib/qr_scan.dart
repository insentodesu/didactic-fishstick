import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'api_client.dart' as api;

// ---------------------------------------------------------------------------
// JS-биндинги для функций из web/index.html
// ---------------------------------------------------------------------------
@JS('initQrScanner')
external void _initQrScanner(
  String containerId,
  JSFunction onResult,
  JSFunction onError,
);

@JS('stopQrScanner')
external void _stopQrScanner(String containerId);

// ---------------------------------------------------------------------------
// Отправка сырого содержимого QR чека на бэкенд.
// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> uploadReceiptQr(String rawQr) async {
  return api.scanReceiptQr(rawQr);
}

// ---------------------------------------------------------------------------
// Экран сканирования QR через браузерный getUserMedia + jsQR.
// Камера запрашивается нативно браузером — разрешение появляется автоматически.
// ---------------------------------------------------------------------------
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final String _viewId;
  bool _handled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewId = 'qr-scanner-${DateTime.now().millisecondsSinceEpoch}';

    // Регистрируем фабрику платформенного вью — создаёт div-контейнер с нужным id.
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return web.HTMLDivElement()
        ..id = _viewId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
    });

    // Запускаем сканер после первого frame, чтобы div успел войти в DOM.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), _startScanner);
    });
  }

  void _startScanner() {
    if (!mounted) return;
    _initQrScanner(
      _viewId,
      ((JSString code) {
        if (!_handled && mounted) {
          _handled = true;
          Navigator.pop(context, code.toDart);
        }
      }).toJS,
      ((JSString err) {
        if (mounted) setState(() => _error = err.toDart);
      }).toJS,
    );
  }

  @override
  void dispose() {
    _stopQrScanner(_viewId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Сканируйте QR чека', style: TextStyle(fontSize: 17)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white54, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Нет доступа к камере:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38)),
                      child: const Text('Назад'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Видеопоток — занимает весь экран
            Positioned.fill(
              child: HtmlElementView(viewType: _viewId),
            ),
            // Рамка прицела
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
          // Подсказка внизу
          Positioned(
            bottom: 60,
            left: 32,
            right: 32,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Наведите камеру на QR-код в нижней части чека. '
                'Данные будут отправлены на сервер для обработки.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
