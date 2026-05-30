import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'api_client.dart' as api;

@JS('initQrScanner')
external void _initQrScanner(
  String containerId,
  JSFunction onResult,
  JSFunction onError,
);

@JS('stopQrScanner')
external void _stopQrScanner(String containerId);

Future<Map<String, dynamic>> uploadReceiptQr(String rawQr) async {
  return api.scanReceiptQr(rawQr);
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final String _viewId;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'qr-scanner-${DateTime.now().millisecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return web.HTMLDivElement()
        ..id = _viewId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
    });
    // initQrScanner вызывается сразу — он показывает HTML-кнопку,
    // которая сама вызовет getUserMedia по нажатию пользователя.
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
        // Ошибка отображается в JS-интерфейсе внутри div
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
        title: const Text('Сканируйте QR чека',
            style: TextStyle(fontSize: 17)),
      ),
      // HtmlElementView занимает весь экран.
      // Вся UI (кнопка, видео, прицел, подсказка) — внутри JS/HTML.
      body: HtmlElementView(viewType: _viewId),
    );
  }
}
