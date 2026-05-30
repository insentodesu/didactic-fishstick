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
//
// Камера запускается ТОЛЬКО по явному тапу пользователя — это требование
// Safari: getUserMedia должен вызываться синхронно из жеста (tap/click).
// ---------------------------------------------------------------------------
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final String _viewId;
  bool _handled = false;
  bool _cameraStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewId = 'qr-scanner-${DateTime.now().millisecondsSinceEpoch}';
    // Регистрируем div-контейнер — он будет в DOM до первого тапа пользователя.
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return web.HTMLDivElement()
        ..id = _viewId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
    });
  }

  // Вызывается синхронно из onTap — сохраняет контекст жеста для Safari.
  void _onStartCamera() {
    setState(() => _cameraStarted = true);
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
          // Платформенный вью всегда в DOM, чтобы div был доступен до тапа.
          Positioned.fill(
            child: HtmlElementView(viewType: _viewId),
          ),

          // Оверлей "включить камеру" — показываем пока камера не запущена.
          if (!_cameraStarted && _error == null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _onStartCamera,
                child: Container(
                  color: Colors.black,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 38),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Нажмите для включения камеры',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Браузер запросит разрешение на доступ к камере',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Ошибка доступа к камере
          if (_error != null)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off,
                        color: Colors.white38, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Нет доступа к камере:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _cameraStarted = false;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38)),
                      child: const Text('Попробовать снова'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Назад',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ],
                ),
              ),
            ),

          // Рамка прицела — только когда камера активна
          if (_cameraStarted && _error == null)
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),

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
              child: Text(
                _cameraStarted && _error == null
                    ? 'Наведите камеру на QR-код в нижней части чека.'
                    : 'QR-код находится в нижней части бумажного чека.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13.5, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
