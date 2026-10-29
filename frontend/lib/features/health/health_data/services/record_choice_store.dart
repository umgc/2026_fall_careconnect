import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One decision about a flagged record, for the audit trail.
class RecordDecisionEntry {
  final DateTime at;

  /// `confirmed`, `keep_both` or `deferred`.
  final String decision;

  /// `source:id` of each version, and of the confirmed one when there is one.
  /// Ids only: no record content, so the log holds no clinical details.
  final List<String> versions;
  final String? chosen;

  const RecordDecisionEntry({
    required this.at,
    required this.decision,
    required this.versions,
    this.chosen,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'decision': decision,
        'versions': versions,
        if (chosen != null) 'chosen': chosen,
      };

  static RecordDecisionEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (at == null) return null;
    return RecordDecisionEntry(
      at: at,
      decision: json['decision']?.toString() ?? '',
      versions: ((json['versions'] as List?) ?? const [])
          .map((v) => v.toString())
          .toList(),
      chosen: json['chosen']?.toString(),
    );
  }
}

/// Remembers how the patient resolved each flagged record, on this device,
/// so they are asked once per record (WBS 6.2.41), and keeps a log of every
/// decision, including "decide later".
///
/// Kept in the frontend: the backend stores each source's records as
/// reported and has no endpoint for these decisions, so they don't follow
/// the patient to another device and aren't in the server audit log.
class RecordChoiceStore {
  static const _key = 'health_data.record_choices';
  static const _logKey = 'health_data.record_decision_log';

  /// Oldest entries are dropped past this, so the log can't grow forever.
  static const maxLogEntries = 500;

  /// The last write queued on this store. Writes read, change, then write
  /// the stored value with awaits in between, so two that overlap could lose
  /// one; queuing them runs each in turn, in call order. Per store, not
  /// shared: Health Data keeps one store, and a shared queue would let a
  /// write left behind by a closed screen hold up every later one.
  Future<void> _lastWrite = Future.value();

  Future<void> _queued(Future<void> Function() write) {
    final done = _lastWrite.then((_) => write());
    // A failed write must not block the ones queued after it.
    _lastWrite = done.catchError((_) {});
    return done;
  }

  /// Conflict key -> encoded choice (see RecordReconciler.encodeChoice).
  Future<Map<String, String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final json = jsonDecode(raw);
      return json is Map
          ? json.map((k, v) => MapEntry(k.toString(), v.toString()))
          : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String conflictKey, String encodedChoice) =>
      _queued(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final all = await load();
          all[conflictKey] = encodedChoice;
          await prefs.setString(_key, jsonEncode(all));
        } catch (_) {
          // Not saved: the patient is asked again next time, nothing is lost.
        }
      });

  /// Every decision, oldest first.
  Future<List<RecordDecisionEntry>> decisionLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_logKey);
      if (raw == null) return [];
      final json = jsonDecode(raw);
      return json is List
          ? json
              .map(RecordDecisionEntry.fromJson)
              .whereType<RecordDecisionEntry>()
              .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> logDecision(RecordDecisionEntry entry) => _queued(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final log = [...await decisionLog(), entry];
          final kept = log.length > maxLogEntries
              ? log.sublist(log.length - maxLogEntries)
              : log;
          await prefs.setString(
              _logKey, jsonEncode(kept.map((e) => e.toJson()).toList()));
        } catch (_) {
          // Logging must never block the patient's decision.
        }
      });
}
