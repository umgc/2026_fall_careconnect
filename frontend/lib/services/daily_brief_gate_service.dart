import 'package:shared_preferences/shared_preferences.dart';

/// STML-2: gates the Daily Memory Brief auto-open to once per day, no
/// earlier than 7am local time, per "first-open-after-7am" (WBS 3.13.2).
///
/// The last-shown marker is scoped per [patientId] so a shared device that
/// switches between patient accounts doesn't skip one patient's brief
/// because another patient's brief was already marked seen today.
class DailyBriefGateService {
  static const _lastShownKeyPrefix = 'stml_daily_brief_last_shown_date_';
  static const _briefEarliestHour = 7;

  /// Returns true if the brief should be shown for [patientId]: it's 7am or
  /// later local time and today's brief hasn't been marked seen yet.
  /// Read-only — call [markSeen] only after the brief actually loads, so a
  /// failed navigation/load doesn't consume the day's trigger.
  static Future<bool> shouldShow(int patientId, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    if (current.hour < _briefEarliestHour) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(current);
    return prefs.getString(_keyFor(patientId)) != todayKey;
  }

  /// Marks today's brief as shown for [patientId]. Call this only after the
  /// brief has successfully loaded.
  static Future<void> markSeen(int patientId, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(patientId), _dateKey(current));
  }

  /// Clears the last-shown marker for [patientId] — for tests/manual QA.
  static Future<void> resetForTesting(int patientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(patientId));
  }

  static String _keyFor(int patientId) => '$_lastShownKeyPrefix$patientId';

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
