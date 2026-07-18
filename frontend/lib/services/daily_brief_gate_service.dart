import 'package:shared_preferences/shared_preferences.dart';

/// STML-2: gates the Daily Memory Brief auto-open to once per day, no
/// earlier than 7am local time, per "first-open-after-7am" (WBS 3.13.2).
class DailyBriefGateService {
  static const _lastShownKey = 'stml_daily_brief_last_shown_date';
  static const _briefEarliestHour = 7;

  /// Returns true exactly once per calendar day, only from 7am onward.
  /// A true result marks today as shown, so calling this again today
  /// (even after another login) returns false until the date rolls over.
  static Future<bool> shouldShowAndMarkSeen({DateTime? now}) async {
    final current = now ?? DateTime.now();
    if (current.hour < _briefEarliestHour) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dateKey(current);
    if (prefs.getString(_lastShownKey) == todayKey) {
      return false;
    }

    await prefs.setString(_lastShownKey, todayKey);
    return true;
  }

  /// Clears the last-shown marker — for tests/manual QA of the gate.
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastShownKey);
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
