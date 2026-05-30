import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Базовый URL.
// В production Flutter PWA раздаётся с того же домена что и Traefik,
// поэтому используем относительный путь /api.
// Для локальной разработки без docker — переключить на полный адрес.
// ---------------------------------------------------------------------------
const _kApiBase = '/api';

// ---------------------------------------------------------------------------
// Хранение токена
// ---------------------------------------------------------------------------

String? _accessToken;

Future<void> _saveToken(String token) async {
  _accessToken = token;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('access_token', token);
}

Future<String?> loadToken() async {
  if (_accessToken != null) return _accessToken;
  final prefs = await SharedPreferences.getInstance();
  _accessToken = prefs.getString('access_token');
  return _accessToken;
}

Future<void> clearToken() async {
  _accessToken = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('access_token');
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

Map<String, String> _headers({bool auth = true}) {
  final h = {'Content-Type': 'application/json'};
  if (auth && _accessToken != null) {
    h['Authorization'] = 'Bearer $_accessToken';
  }
  return h;
}

Uri _uri(String path) => Uri.parse('$_kApiBase$path');

T _decode<T>(http.Response resp) {
  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    return jsonDecode(utf8.decode(resp.bodyBytes)) as T;
  }
  final body = utf8.decode(resp.bodyBytes);
  Map<String, dynamic> err = {};
  try {
    err = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {}
  throw ApiException(
    statusCode: resp.statusCode,
    detail: err['detail']?.toString() ?? body,
  );
}

class ApiException implements Exception {
  final int statusCode;
  final String detail;
  ApiException({required this.statusCode, required this.detail});

  @override
  String toString() => 'ApiException($statusCode): $detail';
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> register({
  required String email,
  required String password,
  String? name,
}) async {
  final resp = await http.post(
    _uri('/auth/register'),
    headers: _headers(auth: false),
    body: jsonEncode({'email': email, 'password': password, if (name != null) 'name': name}),
  );
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveToken(data['access_token'] as String);
  return data;
}

Future<Map<String, dynamic>> login({
  required String email,
  required String password,
}) async {
  final resp = await http.post(
    _uri('/auth/login'),
    headers: _headers(auth: false),
    body: jsonEncode({'email': email, 'password': password}),
  );
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveToken(data['access_token'] as String);
  return data;
}

Future<Map<String, dynamic>> getMe() async {
  await loadToken();
  final resp = await http.get(_uri('/users/me'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Транзакции
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> uploadStatement(
  Uint8List bytes,
  String filename,
) async {
  await loadToken();
  final req = http.MultipartRequest('POST', _uri('/transactions/upload'));
  req.headers['Authorization'] = 'Bearer $_accessToken';
  req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  final streamed = await req.send();
  final resp = await http.Response.fromStream(streamed);
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> getTransactionStats({
  String? dateFrom,
  String? dateTo,
}) async {
  await loadToken();
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo != null) params['date_to'] = dateTo;
  final uri = _uri('/transactions/stats').replace(queryParameters: params.isEmpty ? null : params);
  final resp = await http.get(uri, headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<List<dynamic>> getTransactionsByCategory({String? dateFrom, String? dateTo}) async {
  await loadToken();
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo != null) params['date_to'] = dateTo;
  final uri = _uri('/transactions/categories').replace(queryParameters: params.isEmpty ? null : params);
  final resp = await http.get(uri, headers: _headers());
  return _decode<List<dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Аналитика
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getDashboard() async {
  await loadToken();
  final resp = await http.get(_uri('/analytics/dashboard'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> getFinancialHealth({
  required double monthlyIncome,
  required double monthlyExpense,
  double monthlyDebtPayment = 0,
  double savings = 0,
}) async {
  await loadToken();
  final uri = _uri('/analytics/financial-health').replace(queryParameters: {
    'monthly_income': monthlyIncome.toString(),
    'monthly_expense': monthlyExpense.toString(),
    'monthly_debt_payment': monthlyDebtPayment.toString(),
    'savings': savings.toString(),
  });
  final resp = await http.get(uri, headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> getFinancialDiagnosis({
  required double monthlyIncome,
  required double monthlyExpense,
  double monthlyDebtPayment = 0,
  double savings = 0,
}) async {
  await loadToken();
  final uri = _uri('/analytics/diagnosis').replace(queryParameters: {
    'monthly_income': monthlyIncome.toString(),
    'monthly_expense': monthlyExpense.toString(),
    'monthly_debt_payment': monthlyDebtPayment.toString(),
    'savings': savings.toString(),
  });
  final resp = await http.get(uri, headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> getCreditTrafficLight({
  required double monthlyIncome,
  required double monthlyDebtPayment,
}) async {
  await loadToken();
  final uri = _uri('/analytics/credit-traffic-light').replace(queryParameters: {
    'monthly_income': monthlyIncome.toString(),
    'monthly_debt_payment': monthlyDebtPayment.toString(),
  });
  final resp = await http.get(uri, headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> chatWithAi(String message) async {
  await loadToken();
  final resp = await http.post(
    _uri('/analytics/chat'),
    headers: _headers(),
    body: jsonEncode({'message': message}),
  );
  return _decode<Map<String, dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Подписки
// ---------------------------------------------------------------------------

Future<List<dynamic>> getSubscriptions() async {
  await loadToken();
  final resp = await http.get(_uri('/subscriptions/'), headers: _headers());
  return _decode<List<dynamic>>(resp);
}

Future<Map<String, dynamic>> getSubscriptionStats() async {
  await loadToken();
  final resp = await http.get(_uri('/subscriptions/stats'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<void> scanSubscriptions() async {
  await loadToken();
  await http.post(_uri('/subscriptions/scan'), headers: _headers());
}

// ---------------------------------------------------------------------------
// Инвестиции и цели
// ---------------------------------------------------------------------------

Future<List<dynamic>> getDeposits({double? minAmount}) async {
  await loadToken();
  final params = <String, String>{};
  if (minAmount != null) params['min_amount'] = minAmount.toString();
  final uri = _uri('/investments/deposits').replace(queryParameters: params.isEmpty ? null : params);
  final resp = await http.get(uri, headers: _headers());
  return _decode<List<dynamic>>(resp);
}

Future<List<dynamic>> getSavingsGoals() async {
  await loadToken();
  final resp = await http.get(_uri('/investments/goals'), headers: _headers());
  return _decode<List<dynamic>>(resp);
}

Future<Map<String, dynamic>> createSavingsGoal({
  required String title,
  required double targetAmount,
  String? targetDate,
  String emoji = '🎯',
}) async {
  await loadToken();
  final resp = await http.post(
    _uri('/investments/goals'),
    headers: _headers(),
    body: jsonEncode({
      'title': title,
      'target_amount': targetAmount,
      if (targetDate != null) 'target_date': targetDate,
      'emoji': emoji,
    }),
  );
  return _decode<Map<String, dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Геймификация — Тамагочи
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTamagochi() async {
  await loadToken();
  final resp = await http.get(_uri('/gamification/tamagochi'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> feedTamagochi(double amount) async {
  await loadToken();
  final uri = _uri('/gamification/tamagochi/feed')
      .replace(queryParameters: {'amount': amount.toString()});
  final resp = await http.post(uri, headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> getDailyStreak() async {
  await loadToken();
  final resp = await http.get(_uri('/gamification/streak'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> dailyCheckin() async {
  await loadToken();
  final resp = await http.post(_uri('/gamification/daily-checkin'), headers: _headers());
  return _decode<Map<String, dynamic>>(resp);
}

Future<List<dynamic>> getDailyChallenges() async {
  await loadToken();
  final resp = await http.get(_uri('/gamification/challenges'), headers: _headers());
  return _decode<List<dynamic>>(resp);
}

Future<List<dynamic>> getUnlockedAchievements() async {
  await loadToken();
  final resp = await http.get(_uri('/gamification/achievements/unlocked'), headers: _headers());
  return _decode<List<dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Чеки
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> scanReceiptQr(String qrRaw) async {
  await loadToken();
  final resp = await http.post(
    _uri('/receipts/qr'),
    headers: _headers(),
    body: jsonEncode({'qr_raw': qrRaw}),
  );
  return _decode<Map<String, dynamic>>(resp);
}

Future<List<dynamic>> getReceipts() async {
  await loadToken();
  final resp = await http.get(_uri('/receipts/'), headers: _headers());
  return _decode<List<dynamic>>(resp);
}

// ---------------------------------------------------------------------------
// Уведомления
// ---------------------------------------------------------------------------

Future<List<dynamic>> getNotifications({bool unreadOnly = false}) async {
  await loadToken();
  final uri = _uri('/notifications/').replace(
    queryParameters: unreadOnly ? {'unread_only': 'true'} : null,
  );
  final resp = await http.get(uri, headers: _headers());
  return _decode<List<dynamic>>(resp);
}

Future<void> markAllNotificationsRead() async {
  await loadToken();
  await http.put(_uri('/notifications/read-all'), headers: _headers());
}
