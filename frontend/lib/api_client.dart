import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Base URL — same domain as Traefik in production PWA
// ---------------------------------------------------------------------------
const _kApiBase = '/api';

// ---------------------------------------------------------------------------
// Token storage (access + refresh)
// ---------------------------------------------------------------------------

String? _accessToken;
String? _refreshToken;

Future<void> _saveTokens(String access, String refresh) async {
  _accessToken = access;
  _refreshToken = refresh;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('access_token', access);
  await prefs.setString('refresh_token', refresh);
}

Future<String?> loadToken() async {
  if (_accessToken != null) return _accessToken;
  final prefs = await SharedPreferences.getInstance();
  _accessToken = prefs.getString('access_token');
  _refreshToken = prefs.getString('refresh_token');
  return _accessToken;
}

Future<void> clearAllTokens() async {
  _accessToken = null;
  _refreshToken = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('access_token');
  await prefs.remove('refresh_token');
  await prefs.remove('onboarding_done');
}

Future<bool> isLoggedIn() async => (await loadToken()) != null;

/// Пытается обновить access token через refresh token.
/// Возвращает true при успехе.
Future<bool> tryRefreshTokens() async {
  final prefs = await SharedPreferences.getInstance();
  final rt = _refreshToken ?? prefs.getString('refresh_token');
  if (rt == null) return false;
  try {
    final resp = await http.post(
      _uri('/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': rt}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
      return true;
    }
  } catch (_) {}
  return false;
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

Map<String, String> _headers({bool auth = true}) {
  final h = <String, String>{'Content-Type': 'application/json'};
  if (auth && _accessToken != null) h['Authorization'] = 'Bearer $_accessToken';
  return h;
}

Uri _uri(String path) => Uri.parse('$_kApiBase$path');

T _decode<T>(http.Response resp) {
  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    return jsonDecode(utf8.decode(resp.bodyBytes)) as T;
  }
  final body = utf8.decode(resp.bodyBytes);
  Map<String, dynamic> err = {};
  try { err = jsonDecode(body) as Map<String, dynamic>; } catch (_) {}
  throw ApiException(statusCode: resp.statusCode, detail: err['detail']?.toString() ?? body);
}

/// Выполняет GET с авто-обновлением токена при 401.
Future<T> _getAuth<T>(Uri uri) async {
  await loadToken();
  var resp = await http.get(uri, headers: _headers());
  if (resp.statusCode == 401) {
    final ok = await tryRefreshTokens();
    if (ok) resp = await http.get(uri, headers: _headers());
  }
  return _decode<T>(resp);
}

/// Выполняет POST с авто-обновлением токена при 401.
Future<T> _postAuth<T>(Uri uri, {Object? body}) async {
  await loadToken();
  var resp = await http.post(uri, headers: _headers(), body: body != null ? jsonEncode(body) : null);
  if (resp.statusCode == 401) {
    final ok = await tryRefreshTokens();
    if (ok) resp = await http.post(uri, headers: _headers(), body: body != null ? jsonEncode(body) : null);
  }
  return _decode<T>(resp);
}

class ApiException implements Exception {
  final int statusCode;
  final String detail;
  ApiException({required this.statusCode, required this.detail});
  @override
  String toString() => 'ApiException($statusCode): $detail';
}

// ---------------------------------------------------------------------------
// Auth — email (legacy)
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> register({required String email, required String password, String? name}) async {
  final resp = await http.post(_uri('/auth/register'), headers: _headers(auth: false), body: jsonEncode({'email': email, 'password': password, if (name != null) 'name': name}));
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

Future<Map<String, dynamic>> login({required String email, required String password}) async {
  final resp = await http.post(_uri('/auth/login'), headers: _headers(auth: false), body: jsonEncode({'email': email, 'password': password}));
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

// ---------------------------------------------------------------------------
// Auth — phone
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> registerPhone({required String phone, required String password, String? name}) async {
  final resp = await http.post(
    _uri('/auth/register-phone'),
    headers: _headers(auth: false),
    body: jsonEncode({'phone': phone, 'password': password, if (name != null) 'name': name}),
  );
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

Future<Map<String, dynamic>> loginPhone({required String phone, required String password}) async {
  final resp = await http.post(
    _uri('/auth/login-phone'),
    headers: _headers(auth: false),
    body: jsonEncode({'phone': phone, 'password': password}),
  );
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

Future<Map<String, dynamic>> getMe() async => _getAuth<Map<String, dynamic>>(_uri('/users/me'));

// ---------------------------------------------------------------------------
// Транзакции
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> uploadStatement(Uint8List bytes, String filename) async {
  await loadToken();
  final req = http.MultipartRequest('POST', _uri('/transactions/upload'));
  if (_accessToken != null && _accessToken!.isNotEmpty) {
    req.headers['Authorization'] = 'Bearer $_accessToken';
  }
  req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  final streamed = await req.send();
  if (streamed.statusCode == 401) {
    final ok = await tryRefreshTokens();
    if (ok) {
      final req2 = http.MultipartRequest('POST', _uri('/transactions/upload'));
      req2.headers['Authorization'] = 'Bearer $_accessToken';
      req2.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final s2 = await req2.send();
      return _decode<Map<String, dynamic>>(await http.Response.fromStream(s2));
    }
  }
  return _decode<Map<String, dynamic>>(await http.Response.fromStream(streamed));
}

Future<Map<String, dynamic>> getTransactionStats({String? dateFrom, String? dateTo}) async {
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo != null) params['date_to'] = dateTo;
  return _getAuth<Map<String, dynamic>>(_uri('/transactions/stats').replace(queryParameters: params.isEmpty ? null : params));
}

Future<List<dynamic>> getTransactionsByCategory({String? dateFrom, String? dateTo}) async {
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo != null) params['date_to'] = dateTo;
  return _getAuth<List<dynamic>>(_uri('/transactions/categories').replace(queryParameters: params.isEmpty ? null : params));
}

// ---------------------------------------------------------------------------
// Аналитика
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getDashboard() async => _getAuth<Map<String, dynamic>>(_uri('/analytics/dashboard'));

Future<Map<String, dynamic>> getFinancialHealth({required double monthlyIncome, required double monthlyExpense, double monthlyDebtPayment = 0, double savings = 0}) async =>
    _getAuth<Map<String, dynamic>>(_uri('/analytics/financial-health').replace(queryParameters: {
      'monthly_income': monthlyIncome.toString(), 'monthly_expense': monthlyExpense.toString(),
      'monthly_debt_payment': monthlyDebtPayment.toString(), 'savings': savings.toString(),
    }));

Future<Map<String, dynamic>> getFinancialDiagnosis({required double monthlyIncome, required double monthlyExpense, double monthlyDebtPayment = 0, double savings = 0}) async =>
    _getAuth<Map<String, dynamic>>(_uri('/analytics/diagnosis').replace(queryParameters: {
      'monthly_income': monthlyIncome.toString(), 'monthly_expense': monthlyExpense.toString(),
      'monthly_debt_payment': monthlyDebtPayment.toString(), 'savings': savings.toString(),
    }));

Future<Map<String, dynamic>> getCreditTrafficLight({required double monthlyIncome, required double monthlyDebtPayment}) async =>
    _getAuth<Map<String, dynamic>>(_uri('/analytics/credit-traffic-light').replace(queryParameters: {
      'monthly_income': monthlyIncome.toString(), 'monthly_debt_payment': monthlyDebtPayment.toString(),
    }));

Future<Map<String, dynamic>> chatWithAi(String message) async =>
    _postAuth<Map<String, dynamic>>(_uri('/analytics/chat').replace(queryParameters: {'message': message}));

// ---------------------------------------------------------------------------
// Подписки
// ---------------------------------------------------------------------------

Future<List<dynamic>> getSubscriptions() async => _getAuth<List<dynamic>>(_uri('/subscriptions/'));

Future<Map<String, dynamic>> getSubscriptionStats() async => _getAuth<Map<String, dynamic>>(_uri('/subscriptions/stats'));

Future<void> scanSubscriptions() async => _postAuth<Map<String, dynamic>>(_uri('/subscriptions/scan'));

// ---------------------------------------------------------------------------
// Инвестиции
// ---------------------------------------------------------------------------

Future<List<dynamic>> getDeposits({double? minAmount}) async {
  final params = <String, String>{};
  if (minAmount != null) params['min_amount'] = minAmount.toString();
  return _getAuth<List<dynamic>>(_uri('/investments/deposits').replace(queryParameters: params.isEmpty ? null : params));
}

Future<List<dynamic>> getSavingsGoals() async => _getAuth<List<dynamic>>(_uri('/investments/goals'));

Future<Map<String, dynamic>> createSavingsGoal({required String title, required double targetAmount, String? targetDate, String emoji = '🎯'}) async =>
    _postAuth<Map<String, dynamic>>(_uri('/investments/goals'), body: {
      'title': title, 'target_amount': targetAmount,
      if (targetDate != null) 'target_date': targetDate, 'emoji': emoji,
    });

// ---------------------------------------------------------------------------
// Геймификация
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTamagochi() async => _getAuth<Map<String, dynamic>>(_uri('/gamification/tamagochi'));

Future<Map<String, dynamic>> feedTamagochi(double amount) async =>
    _postAuth<Map<String, dynamic>>(_uri('/gamification/tamagochi/feed').replace(queryParameters: {'amount': amount.toString()}));

Future<Map<String, dynamic>> getDailyStreak() async => _getAuth<Map<String, dynamic>>(_uri('/gamification/streak'));

Future<Map<String, dynamic>> dailyCheckin() async => _postAuth<Map<String, dynamic>>(_uri('/gamification/daily-checkin'));

Future<List<dynamic>> getDailyChallenges() async => _getAuth<List<dynamic>>(_uri('/gamification/challenges'));

Future<List<dynamic>> getUnlockedAchievements() async => _getAuth<List<dynamic>>(_uri('/gamification/achievements/unlocked'));

// ---------------------------------------------------------------------------
// Чеки
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> scanReceiptQr(String qrRaw) async =>
    _postAuth<Map<String, dynamic>>(_uri('/receipts/qr'), body: {'qr_raw': qrRaw});

Future<List<dynamic>> getReceipts() async => _getAuth<List<dynamic>>(_uri('/receipts/'));

// ---------------------------------------------------------------------------
// Уведомления
// ---------------------------------------------------------------------------

Future<List<dynamic>> getNotifications({bool unreadOnly = false}) async =>
    _getAuth<List<dynamic>>(_uri('/notifications/').replace(queryParameters: unreadOnly ? {'unread_only': 'true'} : null));

Future<void> markAllNotificationsRead() async {
  await loadToken();
  await http.put(_uri('/notifications/read-all'), headers: _headers());
}

// ---------------------------------------------------------------------------
// Аналитика — светофор + прогноз + онбординг
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTrafficLight({bool demo = false}) async =>
    _getAuth<Map<String, dynamic>>(_uri('/analytics/traffic-light').replace(queryParameters: demo ? {'demo': 'true'} : null));

Future<Map<String, dynamic>> getForecast({bool demo = false, int months = 6}) async =>
    _getAuth<Map<String, dynamic>>(_uri('/analytics/forecast').replace(queryParameters: {'months': months.toString(), if (demo) 'demo': 'true'}));

Future<Map<String, dynamic>> postOnboarding({
  required double monthlyIncome,
  required bool hasCredits,
  required double monthlyDebtPayment,
  required List<String> goals,
  List<String> barriers = const [],
  String? statementId,
}) async =>
    _postAuth<Map<String, dynamic>>(_uri('/analytics/onboarding'), body: {
      'monthly_income': monthlyIncome,
      'has_credits': hasCredits,
      'monthly_debt_payment': monthlyDebtPayment,
      'goals': goals,
      'barriers': barriers,
      if (statementId != null) 'statement_id': statementId,
    });

// ---------------------------------------------------------------------------
// Простая модель транзакции (для AddTxSheet)
// ---------------------------------------------------------------------------

class Tx {
  final int id;
  final String name, cat, date;
  final double amount;
  const Tx(this.id, this.name, this.cat, this.amount, this.date);
}
