import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/identity_conflict.dart';

class IdentityConflictService {
  final bool useMock;

  /// The sample conflict is opt-in (--dart-define=CARECONNECT_DOB_MOCK=true):
  /// by default no build shows a patient a date of birth that isn't theirs or
  /// reports a change that was never made.
  IdentityConflictService(
      {this.useMock = const bool.fromEnvironment('CARECONNECT_DOB_MOCK')});

  Future<List<IdentityConflict>> fetchPending() async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _mockPending;
    }
    // TODO wire to backend when ready, e.g.:
    // final env = await ApiClient.instance.getJson<Map<String, dynamic>>(
    //   '/v1/api/ehr/identity-conflicts?status=PENDING');
    // return ((env['resources'] as List?) ?? [])
    //     .map((j) => IdentityConflict.fromJson(j as Map<String, dynamic>))
    //     .toList();
    // Until then, only the date-of-birth disagreements this device found
    // between connected sources (see [reportDobDisagreement]).
    return List.unmodifiable(_found.values);
  }

  Future<bool> resolve(int conflictId, {required bool accepted}) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return true;
    }
    // A disagreement this device found is saved on the device (FR-XSRC-10…15
    // patient confirmation, frontend only): Health Data then shows the date
    // the patient chose.
    final found = _found[conflictId];
    if (found != null) {
      final saved = await _saveChoice(found, accepted);
      if (saved) _found.remove(conflictId);
      return saved;
    }
    // TODO wire to backend when ready, e.g.:
    // await ApiClient.instance.postJson(
    //   '/v1/api/ehr/identity-conflicts/$conflictId/resolve',
    //   body: {'status': accepted ? 'ACCEPTED' : 'REJECTED', 'resolvedBy': 'PATIENT'});
    //
    // Until then nothing is saved, so never report success: the screen shows
    // "We couldn't save your choice. Nothing was changed." instead of a false
    // "Date of birth updated." Wire this together with fetchPending.
    return false;
  }

  // ---- Date-of-birth disagreements found between connected sources ----

  /// Disagreements found on this device and not yet decided, by id. Shared
  /// by every instance, so the confirmation screen sees what Health Data
  /// found.
  static final Map<int, IdentityConflict> _found = {};

  /// Ids for found disagreements are negative, so they never collide with a
  /// backend conflict id.
  static int _nextId = -1;

  static const _choicesKey = 'health_data.dob_choices';

  /// The date of birth to show when [current] (the preferred source's) and
  /// [incoming] (another source's) disagree: the patient's saved choice, or
  /// null when they haven't chosen yet, in which case the disagreement is
  /// queued for the confirmation screen and [current] stays shown.
  static Future<DateTime?> reportDobDisagreement({
    required DateTime current,
    required String currentSource,
    required DateTime incoming,
    required String incomingSource,
  }) async {
    final key = _choiceKey(current, incoming);
    final choice = await _loadChoices().then((c) => c[key]);
    if (choice == 'accepted') return incoming;
    if (choice == 'rejected') return current;

    final already = _found.values.any((c) =>
        c.canonicalValueBefore == _format(current) &&
        c.incomingValue == _format(incoming));
    if (!already) {
      final id = _nextId--;
      _found[id] = IdentityConflict(
        id: id,
        fieldName: 'date_of_birth',
        canonicalValueBefore: _format(current),
        incomingValue: _format(incoming),
        canonicalSourceLabel: currentSource,
        incomingSourceLabel: incomingSource,
        status: ConflictStatus.pending,
        detectedAt: DateTime.now(),
      );
    }
    return null;
  }

  @visibleForTesting
  static void clearFound() {
    _found.clear();
    _nextId = -1;
  }

  static Future<bool> _saveChoice(IdentityConflict c, bool accepted) async {
    try {
      final current = _parse(c.canonicalValueBefore);
      final incoming = _parse(c.incomingValue);
      if (current == null || incoming == null) return false;
      final prefs = await SharedPreferences.getInstance();
      final all = await _loadChoices();
      all[_choiceKey(current, incoming)] = accepted ? 'accepted' : 'rejected';
      return await prefs.setString(_choicesKey, jsonEncode(all));
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>> _loadChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_choicesKey);
      if (raw == null) return {};
      final json = jsonDecode(raw);
      return json is Map
          ? json.map((k, v) => MapEntry(k.toString(), v.toString()))
          : {};
    } catch (_) {
      return {};
    }
  }

  /// Hashed, so no date of birth is stored on the device.
  static String _choiceKey(DateTime current, DateTime incoming) => sha256
      .convert(utf8.encode('dob|${_format(current)}|${_format(incoming)}'))
      .toString();

  /// MM/DD/YYYY, as the confirmation screen shows it.
  static String _format(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.year.toString().padLeft(4, '0')}';

  static DateTime? _parse(String v) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v);
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(3)!), int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  static final _mockPending = <IdentityConflict>[
    IdentityConflict(
      id: 1,
      fieldName: 'date_of_birth',
      canonicalValueBefore: '05/14/1980',
      incomingValue: '05/14/1985',
      canonicalSourceLabel: 'Epic',
      incomingSourceLabel: 'Cerner',
      status: ConflictStatus.pending,
      detectedAt: DateTime(2026, 9, 26),
    ),
  ];
}
