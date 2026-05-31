import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Base URL — same domain as Traefik in production PWA
// ---------------------------------------------------------------------------
const _kApiBase = '/api';

// Таймауты: обычный запрос и загрузка файла. Без них спиннер висит вечно
// при медленном/холодном бэкенде.
const _kTimeout = Duration(seconds: 20);
const _kUploadTimeout = Duration(seconds: 120);

Never _timeoutError() => throw ApiException(
      statusCode: 408,
      detail: 'Сервер не отвечает. Проверь соединение и попробуй снова.',
    );

Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) =>
    http.post(uri, headers: headers, body: body).timeout(_kTimeout, onTimeout: _timeoutError);

Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
    http.get(uri, headers: headers).timeout(_kTimeout, onTimeout: _timeoutError);

Future<http.Response> _put(Uri uri, {Map<String, String>? headers}) =>
    http.put(uri, headers: headers).timeout(_kTimeout, onTimeout: _timeoutError);

// ---------------------------------------------------------------------------
// Mock mode — клиентская аналитика из выписки, без обращений к серверу
// ---------------------------------------------------------------------------

bool _mockMode = false;
Map<String, dynamic>? _mockTrafficLight;
Map<String, dynamic>? _mockForecast;
List<TxRecord> _mockTransactions = [];
final List<TxRecord> _localManualTransactions = [];

// Широковещательный стрим — экраны подписываются и перезагружают данные.
final _mockChanges = StreamController<void>.broadcast();
Stream<void> get onMockDataChanged => _mockChanges.stream;

// Стрим изменений транзакций (ручное добавление).
final _txChanges = StreamController<void>.broadcast();
Stream<void> get onTransactionChanged => _txChanges.stream;
void notifyTransactionChanged() => _txChanges.add(null);

void addLocalTransaction(TxRecord tx) {
  _localManualTransactions.insert(0, tx);
  _txChanges.add(null);
}

bool get isMockMode => _mockMode;

void setMockAnalytics({
  required Map<String, dynamic> trafficLight,
  required Map<String, dynamic> forecast,
}) {
  _mockMode = true;
  _mockTrafficLight = trafficLight;
  _mockForecast = forecast;
  _mockTransactions = _kMockTransactions;
  _mockChanges.add(null);
}

void clearMockMode() {
  _mockMode = false;
  _mockTrafficLight = null;
  _mockForecast = null;
  _mockTransactions = [];
  _localManualTransactions.clear();
  _mockChanges.add(null);
}

// ---------------------------------------------------------------------------
// Token storage (access + refresh)
// ---------------------------------------------------------------------------

String? _accessToken;
String? _refreshToken;

bool _isUsableToken(String? token) {
  if (token == null || token.isEmpty) return false;
  final lower = token.toLowerCase();
  return lower != 'null' && lower != 'undefined';
}

Future<void> _saveTokens(String access, String refresh) async {
  _accessToken = access;
  _refreshToken = refresh;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('access_token', access);
  await prefs.setString('refresh_token', refresh);
}

Future<String?> loadToken() async {
  if (_accessToken == null) {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }
  if (!_isUsableToken(_accessToken)) _accessToken = null;
  if (!_isUsableToken(_refreshToken)) _refreshToken = null;
  return _accessToken;
}

Future<void> _clearAuthTokens() async {
  _accessToken = null;
  _refreshToken = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('access_token');
  await prefs.remove('refresh_token');
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
  if (!_isUsableToken(rt)) return false;
  try {
    final resp = await _post(
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
  if (auth && _isUsableToken(_accessToken)) h['Authorization'] = 'Bearer $_accessToken';
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
  var resp = await _get(uri, headers: _headers());
  if (resp.statusCode == 401) {
    final ok = await tryRefreshTokens();
    if (ok) resp = await _get(uri, headers: _headers());
  }
  return _decode<T>(resp);
}

/// Выполняет POST с авто-обновлением токена при 401.
Future<T> _postAuth<T>(Uri uri, {Object? body}) async {
  await loadToken();
  var resp = await _post(uri, headers: _headers(), body: body != null ? jsonEncode(body) : null);
  if (resp.statusCode == 401) {
    final ok = await tryRefreshTokens();
    if (ok) resp = await _post(uri, headers: _headers(), body: body != null ? jsonEncode(body) : null);
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
  final resp = await _post(_uri('/auth/register'), headers: _headers(auth: false), body: jsonEncode({'email': email, 'password': password, if (name != null) 'name': name}));
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

Future<Map<String, dynamic>> login({required String email, required String password}) async {
  final resp = await _post(_uri('/auth/login'), headers: _headers(auth: false), body: jsonEncode({'email': email, 'password': password}));
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

// ---------------------------------------------------------------------------
// Auth — phone
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> registerPhone({required String phone, required String password, String? name}) async {
  final resp = await _post(
    _uri('/auth/register-phone'),
    headers: _headers(auth: false),
    body: jsonEncode({'phone': phone, 'password': password, if (name != null) 'name': name}),
  );
  final data = _decode<Map<String, dynamic>>(resp);
  await _saveTokens(data['access_token'] as String, data['refresh_token'] as String);
  return data;
}

Future<Map<String, dynamic>> loginPhone({required String phone, required String password}) async {
  final resp = await _post(
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

Future<http.Response> _sendStatementUpload(Uint8List bytes, String filename, {required bool withAuth, bool demo = false}) async {
  final req = http.MultipartRequest(
    'POST',
    _uri('/transactions/upload').replace(queryParameters: demo ? {'demo': 'true'} : null),
  );
  if (withAuth && _isUsableToken(_accessToken)) {
    req.headers['Authorization'] = 'Bearer $_accessToken';
  }
  req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  final streamed = await req.send().timeout(_kUploadTimeout, onTimeout: _timeoutError);
  return http.Response.fromStream(streamed);
}

Future<Map<String, dynamic>> uploadStatement(Uint8List bytes, String filename, {bool demo = false}) async {
  await loadToken();
  var resp = await _sendStatementUpload(bytes, filename, withAuth: _isUsableToken(_accessToken), demo: demo);
  if (resp.statusCode == 401 && _isUsableToken(_accessToken)) {
    final ok = await tryRefreshTokens();
    if (ok) resp = await _sendStatementUpload(bytes, filename, withAuth: true, demo: demo);
    if (resp.statusCode == 401) {
      await _clearAuthTokens();
      resp = await _sendStatementUpload(bytes, filename, withAuth: false, demo: demo);
    }
  }
  return _decode<Map<String, dynamic>>(resp);
}

Future<Map<String, dynamic>> uploadDemoStatement() async =>
    uploadStatement(Uint8List(0), 'demo-alfa-statement.xlsx', demo: true);

/// Fire-and-forget: логирует демо-сессию на бэкенде (audit row + docker logs).
Future<void> logDemoSession({String screen = 'auth'}) async {
  try {
    await _post(
      _uri('/analytics/demo-session'),
      headers: _headers(auth: false),
      body: jsonEncode({'source': 'web', 'screen': screen}),
    );
  } catch (_) {}
}

/// Fire-and-forget: ping analytics для видимой активности в demo/mock.
Future<void> pingAnalytics({String screen = 'home', bool demo = true}) async {
  try {
    await _post(
      _uri('/analytics/ping'),
      headers: _headers(auth: false),
      body: jsonEncode({'screen': screen, 'demo': demo}),
    );
  } catch (_) {}
}

/// Fire-and-forget: дергает list transactions (COUNT в Postgres) без ожидания UI.
Future<void> pingTransactionList() async {
  try {
    await _get(_uri('/transactions/').replace(queryParameters: {'page': '1', 'page_size': '1'}), headers: _headers(auth: false));
  } catch (_) {}
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
  await _put(_uri('/notifications/read-all'), headers: _headers());
}

// ---------------------------------------------------------------------------
// Аналитика — светофор + прогноз + онбординг
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTrafficLight({bool demo = false}) async {
  if (_mockMode && _mockTrafficLight != null) {
    pingAnalytics(screen: 'traffic-light', demo: true);
    return _mockTrafficLight!;
  }
  if (demo) pingAnalytics(screen: 'traffic-light', demo: true);
  return _getAuth<Map<String, dynamic>>(_uri('/analytics/traffic-light').replace(queryParameters: demo ? {'demo': 'true'} : null));
}

Future<Map<String, dynamic>> getForecast({bool demo = false, int months = 6}) async {
  if (_mockMode && _mockForecast != null) {
    pingAnalytics(screen: 'forecast', demo: true);
    return _mockForecast!;
  }
  if (demo) pingAnalytics(screen: 'forecast', demo: true);
  return _getAuth<Map<String, dynamic>>(_uri('/analytics/forecast').replace(queryParameters: {'months': months.toString(), if (demo) 'demo': 'true'}));
}

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
// Простая модель транзакции (для AddTxSheet — локальная)
// ---------------------------------------------------------------------------

class Tx {
  final int id;
  final String name, cat, date;
  final double amount;
  const Tx(this.id, this.name, this.cat, this.amount, this.date);
}

// ---------------------------------------------------------------------------
// Полная модель транзакции (для истории)
// ---------------------------------------------------------------------------

class TxRecord {
  final String id;
  final String name;
  final String categoryIcon;
  final String categoryName;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final String source;

  const TxRecord({
    required this.id, required this.name, required this.categoryIcon,
    required this.categoryName, required this.amount, required this.isIncome,
    required this.date, required this.source,
  });

  factory TxRecord.fromJson(Map<String, dynamic> j) {
    final merchant = j['merchant_name'] as String?;
    final desc = j['description'] as String?;
    final income = j['is_income'] as bool? ?? false;
    return TxRecord(
      id: j['id']?.toString() ?? '',
      name: (merchant?.isNotEmpty == true ? merchant : desc) ?? 'Транзакция',
      categoryIcon: j['category_icon'] as String? ?? (income ? '💰' : '📦'),
      categoryName: j['category'] as String? ?? (income ? 'Доход' : 'Прочее'),
      amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
      isIncome: income,
      date: j['transaction_date'] != null ? DateTime.parse(j['transaction_date'] as String) : DateTime.now(),
      source: j['source'] as String? ?? 'bank_statement',
    );
  }
}

// ---------------------------------------------------------------------------
// История транзакций
// ---------------------------------------------------------------------------

Future<List<TxRecord>> getTransactionHistory({int page = 1, int pageSize = 100, bool? isIncome, bool demo = false}) async {
  if (_mockMode) {
    pingTransactionList();
    return [..._localManualTransactions, ..._mockTransactions];
  }
  if (demo) {
    pingTransactionList();
    return [..._localManualTransactions, ..._kDemoTransactions];
  }
  final params = <String, String>{'page': page.toString(), 'page_size': pageSize.toString()};
  if (isIncome != null) params['is_income'] = isIncome.toString();
  final data = await _getAuth<Map<String, dynamic>>(_uri('/transactions/').replace(queryParameters: params));
  final items = data['items'] as List? ?? [];
  return items.map((e) => TxRecord.fromJson(e as Map<String, dynamic>)).toList();
}

Future<TxRecord> postManualTransaction({
  required String description,
  required double amount,
  required bool isIncome,
  String? categoryName,
}) async {
  final body = <String, dynamic>{
    'description': description,
    'amount': amount,
    'is_income': isIncome,
    if (categoryName != null) 'category_name': categoryName,
  };
  final data = await _postAuth<Map<String, dynamic>>(_uri('/transactions/manual'), body: body);
  return TxRecord.fromJson(data);
}

// ---------------------------------------------------------------------------
// Демо-транзакции (PDN 47 %, доход 92 k, долг 43 k — соответствуют demo()-данным экранов)
// ---------------------------------------------------------------------------

final _kDemoTransactions = <TxRecord>[
  TxRecord(id: 'd01', name: 'Зарплата', categoryIcon: '💰', categoryName: 'Доход', amount: 80000, isIncome: true, date: DateTime(2026, 5, 15), source: 'mock'),
  TxRecord(id: 'd02', name: 'Подработка', categoryIcon: '💰', categoryName: 'Доход', amount: 12000, isIncome: true, date: DateTime(2026, 5, 20), source: 'mock'),
  TxRecord(id: 'd03', name: 'Ипотека', categoryIcon: '🏦', categoryName: 'Финансы', amount: 32000, isIncome: false, date: DateTime(2026, 5, 10), source: 'mock'),
  TxRecord(id: 'd04', name: 'Автокредит', categoryIcon: '💳', categoryName: 'Финансы', amount: 11264, isIncome: false, date: DateTime(2026, 5, 10), source: 'mock'),
  TxRecord(id: 'd05', name: 'Продукты', categoryIcon: '🍕', categoryName: 'Еда', amount: 8500, isIncome: false, date: DateTime(2026, 5, 25), source: 'mock'),
  TxRecord(id: 'd06', name: 'Яндекс Такси', categoryIcon: '🚗', categoryName: 'Транспорт', amount: 3200, isIncome: false, date: DateTime(2026, 5, 18), source: 'mock'),
  TxRecord(id: 'd07', name: 'Зарплата', categoryIcon: '💰', categoryName: 'Доход', amount: 80000, isIncome: true, date: DateTime(2026, 4, 15), source: 'mock'),
  TxRecord(id: 'd08', name: 'Подработка', categoryIcon: '💰', categoryName: 'Доход', amount: 12000, isIncome: true, date: DateTime(2026, 4, 22), source: 'mock'),
  TxRecord(id: 'd09', name: 'Ипотека', categoryIcon: '🏦', categoryName: 'Финансы', amount: 32000, isIncome: false, date: DateTime(2026, 4, 10), source: 'mock'),
  TxRecord(id: 'd10', name: 'Автокредит', categoryIcon: '💳', categoryName: 'Финансы', amount: 11264, isIncome: false, date: DateTime(2026, 4, 10), source: 'mock'),
  TxRecord(id: 'd11', name: 'Кафе', categoryIcon: '☕', categoryName: 'Еда', amount: 5600, isIncome: false, date: DateTime(2026, 4, 20), source: 'mock'),
  TxRecord(id: 'd12', name: 'ЖКУ', categoryIcon: '🏠', categoryName: 'Коммунальные', amount: 6800, isIncome: false, date: DateTime(2026, 4, 12), source: 'mock'),
];

// ---------------------------------------------------------------------------
// Мок-транзакции (соответствуют моковой аналитике Альфа-Банк фев–май 2026)
// ---------------------------------------------------------------------------

final _kMockTransactions = <TxRecord>[
  TxRecord(id: 'm01', name: 'Зарплата', categoryIcon: '💰', categoryName: 'Доход', amount: 44210, isIncome: true, date: DateTime(2026, 5, 15), source: 'mock'),
  TxRecord(id: 'm02', name: 'Фриланс', categoryIcon: '💰', categoryName: 'Доход', amount: 25025, isIncome: true, date: DateTime(2026, 5, 10), source: 'mock'),
  TxRecord(id: 'm03', name: 'Пятёрочка', categoryIcon: '🍕', categoryName: 'Еда', amount: 1847, isIncome: false, date: DateTime(2026, 5, 28), source: 'mock'),
  TxRecord(id: 'm04', name: 'Wildberries', categoryIcon: '🛍️', categoryName: 'Покупки', amount: 3200, isIncome: false, date: DateTime(2026, 5, 12), source: 'mock'),
  TxRecord(id: 'm05', name: 'Яндекс Такси', categoryIcon: '🚗', categoryName: 'Транспорт', amount: 540, isIncome: false, date: DateTime(2026, 5, 11), source: 'mock'),
  TxRecord(id: 'm06', name: 'Кредитный платёж', categoryIcon: '💳', categoryName: 'Финансы', amount: 5000, isIncome: false, date: DateTime(2026, 5, 20), source: 'mock'),
  TxRecord(id: 'm07', name: 'МТС', categoryIcon: '📱', categoryName: 'Связь', amount: 203, isIncome: false, date: DateTime(2026, 5, 1), source: 'mock'),
  TxRecord(id: 'm08', name: 'Яндекс Плюс', categoryIcon: '🎵', categoryName: 'Подписки', amount: 299, isIncome: false, date: DateTime(2026, 5, 3), source: 'mock'),
  TxRecord(id: 'm09', name: 'Зарплата', categoryIcon: '💰', categoryName: 'Доход', amount: 43099, isIncome: true, date: DateTime(2026, 4, 15), source: 'mock'),
  TxRecord(id: 'm10', name: 'ВкусВилл', categoryIcon: '🍕', categoryName: 'Еда', amount: 2340, isIncome: false, date: DateTime(2026, 4, 22), source: 'mock'),
  TxRecord(id: 'm11', name: 'ЖКУ', categoryIcon: '🏠', categoryName: 'Коммунальные', amount: 4800, isIncome: false, date: DateTime(2026, 4, 12), source: 'mock'),
  TxRecord(id: 'm12', name: 'Кредитный платёж', categoryIcon: '💳', categoryName: 'Финансы', amount: 5000, isIncome: false, date: DateTime(2026, 4, 20), source: 'mock'),
  TxRecord(id: 'm13', name: 'Кинопоиск', categoryIcon: '🎬', categoryName: 'Подписки', amount: 399, isIncome: false, date: DateTime(2026, 4, 5), source: 'mock'),
  TxRecord(id: 'm14', name: 'Яндекс Такси', categoryIcon: '🚗', categoryName: 'Транспорт', amount: 780, isIncome: false, date: DateTime(2026, 4, 10), source: 'mock'),
  TxRecord(id: 'm15', name: 'Зарплата', categoryIcon: '💰', categoryName: 'Доход', amount: 44210, isIncome: true, date: DateTime(2026, 3, 15), source: 'mock'),
  TxRecord(id: 'm16', name: 'Перекрёсток', categoryIcon: '🍕', categoryName: 'Еда', amount: 1560, isIncome: false, date: DateTime(2026, 3, 20), source: 'mock'),
  TxRecord(id: 'm17', name: 'Кредитный платёж', categoryIcon: '💳', categoryName: 'Финансы', amount: 5000, isIncome: false, date: DateTime(2026, 3, 20), source: 'mock'),
  TxRecord(id: 'm18', name: 'Интернет', categoryIcon: '🌐', categoryName: 'Связь', amount: 203, isIncome: false, date: DateTime(2026, 3, 1), source: 'mock'),
  TxRecord(id: 'm19', name: 'Аптека', categoryIcon: '💊', categoryName: 'Здоровье', amount: 1200, isIncome: false, date: DateTime(2026, 3, 25), source: 'mock'),
  TxRecord(id: 'm20', name: 'СберМаркет', categoryIcon: '🛒', categoryName: 'Еда', amount: 2890, isIncome: false, date: DateTime(2026, 3, 8), source: 'mock'),
];
