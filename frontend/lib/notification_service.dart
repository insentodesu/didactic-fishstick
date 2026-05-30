import 'dart:js_interop';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------
const _kDailyEnabled = 'notif_daily_enabled';
const _kWeeklyEnabled = 'notif_weekly_enabled';
const _kDailyHour = 'notif_daily_hour';
const _kDailyMin = 'notif_daily_min';
const _kLastExpenseDate = 'last_expense_date';
const _kLastStatementDate = 'last_statement_date';

// ---------------------------------------------------------------------------

class NotificationSettings {
  final bool dailyEnabled;
  final bool weeklyEnabled;
  final int dailyHour;
  final int dailyMin;

  const NotificationSettings({
    required this.dailyEnabled,
    required this.weeklyEnabled,
    required this.dailyHour,
    required this.dailyMin,
  });

  NotificationSettings copyWith({
    bool? dailyEnabled,
    bool? weeklyEnabled,
    int? dailyHour,
    int? dailyMin,
  }) =>
      NotificationSettings(
        dailyEnabled: dailyEnabled ?? this.dailyEnabled,
        weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
        dailyHour: dailyHour ?? this.dailyHour,
        dailyMin: dailyMin ?? this.dailyMin,
      );
}

// ---------------------------------------------------------------------------

class NotificationService {
  // iOS Safari and some browsers don't support the Notifications API at all.
  // Guard every access so the app doesn't crash on unsupported platforms.
  static String get permission {
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'default';
    }
  }

  static bool get isGranted => permission == 'granted';
  static bool get isDenied => permission == 'denied';
  static bool get isSupported {
    try {
      web.Notification.permission; // throws if not supported
      return true;
    } catch (_) {
      return false;
    }
  }

  // Requests browser notification permission.
  static Future<bool> requestPermission() async {
    try {
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  // Shows a browser notification immediately.
  static void show(String title, String body) {
    if (!isGranted) return;
    web.Notification(
      title,
      web.NotificationOptions(body: body),
    );
  }

  static void showDailyReminder() => show(
        '💰 Не забудьте внести траты',
        'Запишите расходы за сегодня — питомец голоден без вашей активности!',
      );

  static void showWeeklyReminder() => show(
        '📊 Время актуализировать данные',
        'Выгрузите выписку из банка — мы проверим точность вашего учёта для более корректных данных.',
      );

  // ---------------------------------------------------------------------------
  // Settings persistence
  // ---------------------------------------------------------------------------

  static Future<NotificationSettings> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    return NotificationSettings(
      dailyEnabled: p.getBool(_kDailyEnabled) ?? false,
      weeklyEnabled: p.getBool(_kWeeklyEnabled) ?? false,
      dailyHour: p.getInt(_kDailyHour) ?? 21,
      dailyMin: p.getInt(_kDailyMin) ?? 0,
    );
  }

  static Future<void> saveSettings(NotificationSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyEnabled, s.dailyEnabled);
    await p.setBool(_kWeeklyEnabled, s.weeklyEnabled);
    await p.setInt(_kDailyHour, s.dailyHour);
    await p.setInt(_kDailyMin, s.dailyMin);
  }

  // ---------------------------------------------------------------------------
  // In-app reminder checks
  // ---------------------------------------------------------------------------

  // True if the user hasn't logged an expense today and daily reminder is ON.
  static Future<bool> needsDailyReminder() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kDailyEnabled) ?? false)) return false;
    final raw = p.getString(_kLastExpenseDate);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    final now = DateTime.now();
    return last.year != now.year ||
        last.month != now.month ||
        last.day != now.day;
  }

  // True if it's Sunday and no statement was uploaded in the last 7 days.
  static Future<bool> needsWeeklyReminder() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kWeeklyEnabled) ?? false)) return false;
    if (DateTime.now().weekday != DateTime.sunday) return false;
    final raw = p.getString(_kLastStatementDate);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last).inDays >= 6;
  }

  // Call this whenever the user adds a transaction.
  static Future<void> markExpenseLogged() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kLastExpenseDate, DateTime.now().toIso8601String());
  }

  // Call this after a successful statement upload.
  static Future<void> markStatementUploaded() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kLastStatementDate, DateTime.now().toIso8601String());
  }
}
