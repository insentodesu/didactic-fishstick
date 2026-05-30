import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client.dart' as api;

// ---------------------------------------------------------------------------
// Отправка сырого содержимого QR чека на бэкенд.
//
// Клиент НЕ разбирает QR. Сервер по реквизитам ФН (fn, i, fp и т.д.) сам
// запросит детализацию у ОФД/ФНС и вернёт распознанные позиции/сумму.
//
// TODO(backend): реализовать запрос к вашему API. Пример с http:
//
//   final resp = await http.post(
//     Uri.parse('$apiBase/receipts'),
//     headers: {'Content-Type': 'application/json'},
//     body: jsonEncode({'qr': rawQr}),
//   );
//   if (resp.statusCode != 200) throw Exception('receipt upload failed');
//
// Сейчас — заглушка с задержкой, чтобы UI работал end-to-end.
// ---------------------------------------------------------------------------
Future<Map<String, dynamic>> uploadReceiptQr(String rawQr) async {
  return api.scanReceiptQr(rawQr);
}

// ---------------------------------------------------------------------------
// Экран сканирования. Возвращает сырую строку QR через Navigator.pop.
// В браузере mobile_scanner использует getUserMedia (нужен HTTPS + разрешение
// на камеру).
// ---------------------------------------------------------------------------
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    Navigator.pop(context, code); // возвращаем сырую строку QR
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
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Рамка прицела
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
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
                style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}