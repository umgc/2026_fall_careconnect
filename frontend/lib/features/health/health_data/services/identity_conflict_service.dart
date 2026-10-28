import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/api_client.dart';
import '../../../../services/user_role_storage_service.dart';
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
    // The backend's pending conflicts (GET /v1/api/ehr/identity-conflicts,
    // #432), each with its masked identityCheck and source labels, plus the
    // date-of-birth disagreements this device found between connected
    // sources (see [reportDobDisagreement]) for the signed-in patient. A pair
    // of dates the backend already has is shown once, as the backend's.
    // Throws when the backend can't be checked, so the screen says so
    // instead of "all caught up".
    final owner = await _owner();
    final server = await _fetchServer("PENDING");
    _shown
      ..clear()
      ..addAll({for (final s in server) s.id: (owner: owner, conflict: s)});
    final local = _found.values
        .where((f) => f.owner == owner)
        .map((f) => f.conflict)
        .where((l) => !server.any((s) => _sameDates(s, l) != 0));
    return List.unmodifiable([...server, ...local]);
  }

  Future<List<IdentityConflict>> fetchAccepted() async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _mockPending;
    }
    final owner = await _owner();
    final server = await _fetchServer("ACCEPTED");
    _shown
      ..clear()
      ..addAll({for (final s in server) s.id: (owner: owner, conflict: s)});
    final local = _found.values
        .where((f) => f.owner == owner)
        .map((f) => f.conflict)
        .where((l) => !server.any((s) => _sameDates(s, l) != 0));
    return List.unmodifiable([...server, ...local]);
  }

  Future<List<IdentityConflict>> fetchRejected() async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _mockPending;
    }
    final owner = await _owner();
    final server = await _fetchServer("REJECTED");
    _shown
      ..clear()
      ..addAll({for (final s in server) s.id: (owner: owner, conflict: s)});
    final local = _found.values
        .where((f) => f.owner == owner)
        .map((f) => f.conflict)
        .where((l) => !server.any((s) => _sameDates(s, l) != 0));
    return List.unmodifiable([...server, ...local]);
  }


  /// The patient's pending date-of-birth conflicts from the backend. A 400,
  /// 403, 404 or 409 means the backend has none this caller can confirm (not
  /// a patient, or no patient record); anything else is rethrown.
  Future<List<IdentityConflict>> _fetchServer(final String status) async {
    final Map<String, dynamic> env;
    try {
      env = await ApiClient.instance.getJson<Map<String, dynamic>>(
        _path,
        query: {'status': status},
        parser: (json) =>
            json is Map<String, dynamic> ? json : <String, dynamic>{},
      );
    } on DioException catch (e) {
      final inner = e.error;
      final status = e.response?.statusCode ??
          (inner is ApiException ? inner.status : null);
      if (const {400, 403, 404, 409}.contains(status)) return const [];
      rethrow;
    }
    final out = <IdentityConflict>[];
    for (final j in (env['resources'] as List?) ?? const []) {
      if (j is! Map) continue;
      final c = IdentityConflict.fromJson(Map<String, dynamic>.from(j));
      // Only a pending date of birth is the patient's to confirm here, and
      // only a positive id can be sent back to the backend.
      if (!c.isDob || !c.isPending || c.id <= 0) continue;
      out.add(_withShownDates(c));
    }
    return out;
  }

  static const _path = '/v1/api/ehr/identity-conflicts';

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
      // Another patient's disagreement is never theirs to decide.
      final owner = await _owner();
      if (found.owner != owner) return false;
      final saved = await _saveChoice(owner, found.conflict, accepted);
      if (saved) _found.remove(conflictId);
      return saved;
    }
    // A backend conflict (positive id) is saved through the endpoint (#432).
    // Anything but a 2xx means nothing was saved, so it is never reported as
    // saved: the screen says "We couldn't save your choice. Nothing was
    // changed." and keeps the card.
    if (conflictId <= 0) return false;
    try {
      await ApiClient.instance.postJson<dynamic>(
        '$_path/$conflictId/resolve',
        body: {
          'status': accepted ? 'ACCEPTED' : 'REJECTED',
          'resolvedBy': 'PATIENT',
        },
      );
    } catch (_) {
      return false;
    }
    await rememberServerChoice(conflictId, accepted);
    return true;
  }

  /// Once the backend has saved [conflictId], the same choice is kept on the
  /// device for that pair of dates, and a matching disagreement this device
  /// found is dropped, so neither this screen nor Health Data asks again.
  static Future<void> rememberServerChoice(int id, bool accepted) async {
    final shown = _shown.remove(id);
    if (shown == null || shown.owner != await _owner()) return;
    final c = shown.conflict;
    await _saveChoice(shown.owner, c, accepted);
    // The same two dates in the other order are the same question, so that
    // pair is decided too: Use new date here keeps its current date
    // (DEF-EHR-REC-09).
    await _saveChoice(
        shown.owner,
        IdentityConflict(
            id: c.id,
            fieldName: c.fieldName,
            canonicalValueBefore: c.incomingValue,
            incomingValue: c.canonicalValueBefore),
        !accepted);
    _found.removeWhere(
        (_, f) => f.owner == shown.owner && _sameDates(c, f.conflict) != 0);
  }

  /// The backend sends dates as ISO (1980-05-14); the screen and the
  /// device-found conflicts use MM/DD/YYYY. Anything else is left as is.
  static IdentityConflict _withShownDates(IdentityConflict c) {
    String shown(String v) {
      final d = _parseAny(v);
      return d == null ? v : _format(d);
    }

    return IdentityConflict(
      id: c.id,
      fieldName: c.fieldName,
      canonicalValueBefore: shown(c.canonicalValueBefore),
      incomingValue: shown(c.incomingValue),
      canonicalSourceLabel: c.canonicalSourceLabel,
      incomingSourceLabel: c.incomingSourceLabel,
      status: c.status,
      detectedAt: c.detectedAt,
      identityCheck: c.identityCheck,
    );
  }

  /// 1 when [a] and [b] hold the same two dates in the same order, -1 in
  /// the other order (one source's current is the other's new), else 0.
  static int _sameDates(IdentityConflict a, IdentityConflict b) {
    final a1 = _parseAny(a.canonicalValueBefore);
    final a2 = _parseAny(a.incomingValue);
    if (a1 == null || a2 == null) return 0;
    final b1 = _parseAny(b.canonicalValueBefore);
    final b2 = _parseAny(b.incomingValue);
    if (a1 == b1 && a2 == b2) return 1;
    if (a1 == b2 && a2 == b1) return -1;
    return 0;
  }

  /// MM/DD/YYYY or ISO (YYYY-MM-DD, with or without a time), else null.
  static DateTime? _parseAny(String v) {
    final mdy = _parse(v.trim());
    if (mdy != null) return mdy;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v.trim());
    if (m == null) return null;
    return _date(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// Null for an impossible date (02/30, month 13): DateTime would roll it
  /// over to another real date, and the patient would be shown that one
  /// (DEF-EHR-REC-10).
  static DateTime? _date(int y, int m, int d) {
    final date = DateTime(y, m, d);
    return date.year == y && date.month == m && date.day == d ? date : null;
  }

  // ---- Date-of-birth disagreements found between connected sources ----

  /// Disagreements found on this device and not yet decided, by id, each
  /// tagged with the patient it belongs to. Shared by every instance, so the
  /// confirmation screen sees what Health Data found; cleared on logout
  /// ([clearFound]).
  static final Map<int, ({String owner, IdentityConflict conflict})> _found =
      {};

  /// Ids for found disagreements are negative, so they never collide with a
  /// backend conflict id.
  static int _nextId = -1;

  /// The backend conflicts [fetchPending] last returned, by id, each tagged
  /// with the patient it was loaded for. [resolve] uses them to keep a saved
  /// choice on the device too.
  static final Map<int, ({String owner, IdentityConflict conflict})> _shown =
      {};

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
    final owner = await _owner();
    final key = _choiceKey(owner, current, incoming);
    final choice = await _loadChoices().then((c) => c[key]);
    if (choice == 'accepted') return incoming;
    if (choice == 'rejected') return current;

    final already = _found.values.any((f) =>
        f.owner == owner &&
        f.conflict.canonicalValueBefore == _format(current) &&
        f.conflict.incomingValue == _format(incoming));
    if (!already) {
      final id = _nextId--;
      _found[id] = (owner: owner, conflict: IdentityConflict(
        id: id,
        fieldName: 'date_of_birth',
        canonicalValueBefore: _format(current),
        incomingValue: _format(incoming),
        canonicalSourceLabel: currentSource,
        incomingSourceLabel: incomingSource,
        status: ConflictStatus.pending,
        detectedAt: DateTime.now(),
      ));
    }
    return null;
  }

  /// Forgets every undecided disagreement and the backend conflicts last
  /// shown. Called on logout so the next
  /// account signed in during this app session never sees them.
  static void clearFound() {
    _found.clear();
    _shown.clear();
    _nextId = -1;
  }

  /// The signed-in patient the disagreements belong to: their patient id,
  /// else their user id, else '' when nobody is signed in.
  static Future<String> _owner() async {
    try {
      final storage = UserRoleStorageService.instance;
      final patientId = await storage.getPatientId();
      if (patientId != null) return 'patient:$patientId';
      final userId = await storage.getUserId();
      if (userId != null) return 'user:$userId';
    } catch (_) {
      // Storage unavailable: treat as signed out.
    }
    return '';
  }

  static Future<bool> _saveChoice(
      String owner, IdentityConflict c, bool accepted) async {
    try {
      final current = _parse(c.canonicalValueBefore);
      final incoming = _parse(c.incomingValue);
      if (current == null || incoming == null) return false;
      final prefs = await SharedPreferences.getInstance();
      final all = await _loadChoices();
      all[_choiceKey(owner, current, incoming)] = accepted ? 'accepted' : 'rejected';
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

  /// Hashed, so no date of birth is stored on the device. Includes the
  /// patient, so one patient's choice never decides another's date.
  static String _choiceKey(String owner, DateTime current, DateTime incoming) =>
      sha256
          .convert(utf8.encode(
              'dob|$owner|${_format(current)}|${_format(incoming)}'))
          .toString();

  /// MM/DD/YYYY, as the confirmation screen shows it.
  static String _format(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.year.toString().padLeft(4, '0')}';

  static DateTime? _parse(String v) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v);
    if (m == null) return null;
    return _date(
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
      identityCheck: IdentityCheck.of(IdentityCheckType.phone, '4821'),
    ),
  ];
}
