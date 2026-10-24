import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../config/env_constant.dart';

/// Client for the athenahealth connection lifecycle (AthenaController).
///
/// athenahealth uses 2-legged OAuth (client credentials, held by the
/// backend), so unlike Epic and Medicare there is no sign-in page and no
/// browser round trip: connecting is the patient's in-app consent.
///   GET  /api/athena/status     -> { connected, status, reason? }
///   POST /api/athena/connect    { "consent": true }
///                               -> { connected, status, reason?, sync? }
///   POST /api/athena/sync       -> { status, syncedAt, types: [...] }
///   POST /api/athena/disconnect -> { disconnected, removed }
/// Errors are `{ "code": "..." }`. Patient role only (403 otherwise). The
/// whole surface is 404 when the server runs with careconnect.athena.enabled
/// off, e.g. before the athena credentials are set in the environment. Like
/// Epic's tile, the app then still offers Connect (status reads as not
/// connected) and Connect says athenahealth isn't available.
///
/// On a 401 every call refreshes the token once and retries, the same rule
/// as MedicareConnectService.
class AthenaConnectService {
  AthenaConnectService();

  /// Swap in a fake for widget tests.
  static AthenaConnectService instance = AthenaConnectService();

  static String get _base => '${getBackendBaseUrl()}/api/athena';

  /// True when the device has no network connection. Replaceable in tests.
  static Future<bool> Function() isOffline = () async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false; // Unknown: let the request decide.
    }
  };

  /// Sends a request; on 401 refreshes the token once and retries.
  static Future<http.Response> _send(
      Future<http.Response> Function(Map<String, String> headers)
          request) async {
    final first = await request(await ApiService.getAuthHeaders());
    if (first.statusCode != 401) return first;
    try {
      final refreshed = await AuthService.forceRefreshToken();
      if (refreshed == null) return first;
    } catch (_) {
      return first;
    }
    return request(await ApiService.getAuthHeaders());
  }

  static Map<String, String> _jsonHeaders(Map<String, String> h) =>
      {...h, 'Content-Type': 'application/json'};

  /// Returns null when the status can't be checked (network/server error),
  /// so the tile says "couldn't check" instead of "not connected".
  Future<AthenaStatus?> status() async {
    try {
      final resp =
          await _send((h) => http.get(Uri.parse('$_base/status'), headers: h));
      if (resp.statusCode == 404 || _code(resp) == 'DISABLED') {
        return AthenaStatus.unavailable;
      }
      if (resp.statusCode == 403) return AthenaStatus.notPatient;
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      return body is Map<String, dynamic> ? AthenaStatus.fromJson(body) : null;
    } catch (_) {
      return null;
    }
  }

  /// Records consent, links the athena chart and runs the first sync.
  /// Only call after the patient has agreed to the consent text.
  /// Throws [AthenaConnectException] when the request itself fails; a chart
  /// that can't be linked is a normal result with a [AthenaStatus.reason].
  Future<AthenaStatus> connect() async {
    if (await isOffline()) {
      throw const AthenaConnectException(AthenaConnectError.offline);
    }
    final resp = await _post('connect', body: {'consent': true});
    final body = _decode(resp);
    if (body == null) throw const AthenaConnectException(AthenaConnectError.server);
    return AthenaStatus.fromJson(body);
  }

  /// Manual refresh of the patient's athena records.
  Future<AthenaSyncResult> sync() async {
    if (await isOffline()) {
      throw const AthenaConnectException(AthenaConnectError.offline);
    }
    final resp = await _post('sync');
    final body = _decode(resp);
    if (body == null) throw const AthenaConnectException(AthenaConnectError.server);
    return AthenaSyncResult.fromJson(body);
  }

  /// True when the backend confirms the disconnect (its deletes committed).
  Future<bool> disconnect() async {
    try {
      final resp = await _send(
          (h) => http.post(Uri.parse('$_base/disconnect'), headers: h));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _post(String path, {Object? body}) async {
    try {
      return await _send((h) => http.post(Uri.parse('$_base/$path'),
          headers: _jsonHeaders(h),
          body: body == null ? null : jsonEncode(body)));
    } catch (_) {
      throw const AthenaConnectException(AthenaConnectError.network);
    }
  }

  /// The JSON body of a 200, or throws the error its status/code means.
  static Map<String, dynamic>? _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      throw AthenaConnectException(
          AthenaConnectError.fromResponse(resp.statusCode, _code(resp)));
    }
    try {
      final body = jsonDecode(resp.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  static String? _code(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      return body is Map ? body['code']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}

/// Why athena is not connected, from the backend's `reason` code.
enum AthenaNotConnectedReason {
  notConsented,
  notLinked,
  noPatientProfile,
  incompleteProfile,
  notMatched,
  ambiguousMatch,
  linkConflict,
  sourceUnavailable,
  unknown;

  static AthenaNotConnectedReason parse(String? code) {
    switch (code?.trim().toUpperCase()) {
      case 'NOT_CONSENTED':
        return notConsented;
      case 'NOT_LINKED':
        return notLinked;
      case 'NO_PATIENT_PROFILE':
        return noPatientProfile;
      case 'INCOMPLETE_PROFILE':
        return incompleteProfile;
      case 'NOT_MATCHED':
        return notMatched;
      case 'AMBIGUOUS_MATCH':
        return ambiguousMatch;
      case 'LINK_CONFLICT':
        return linkConflict;
      case 'SOURCE_UNAVAILABLE':
        return sourceUnavailable;
      default:
        return unknown;
    }
  }
}

class AthenaStatus {
  final bool connected;

  /// Why not connected; null when connected.
  final AthenaNotConnectedReason? reason;

  /// The first sync, on a connect that linked the chart.
  final AthenaSyncResult? sync;

  /// False when the server has athenahealth turned off (404). Shown as not
  /// connected, as Epic is; Connect then reports it isn't available.
  final bool available;

  /// The signed-in user is not a patient (403): show nothing.
  final bool forPatient;

  const AthenaStatus({
    required this.connected,
    this.reason,
    this.sync,
    this.available = true,
    this.forPatient = true,
  });

  static const unavailable = AthenaStatus(
      connected: false,
      available: false,
      reason: AthenaNotConnectedReason.sourceUnavailable);
  static const notPatient = AthenaStatus(connected: false, forPatient: false);

  /// False when the tile and banners should stay hidden: only for a user
  /// who isn't a patient. A server with athena off still shows Connect.
  bool get shown => forPatient;

  factory AthenaStatus.fromJson(Map<String, dynamic> json) {
    final connected = json['connected'] == true ||
        json['status']?.toString().toUpperCase() == 'CONNECTED';
    final sync = json['sync'];
    return AthenaStatus(
      connected: connected,
      reason: connected
          ? null
          : AthenaNotConnectedReason.parse(json['reason']?.toString()),
      sync: sync is Map<String, dynamic> ? AthenaSyncResult.fromJson(sync) : null,
    );
  }
}

/// What one sync did, per FHIR resource type (AthenaSyncResult).
class AthenaSyncResult {
  /// False when no token could be obtained, so nothing was attempted.
  final bool completed;
  final DateTime? syncedAt;
  final List<AthenaTypeResult> types;

  const AthenaSyncResult(
      {required this.completed, this.syncedAt, this.types = const []});

  factory AthenaSyncResult.fromJson(Map<String, dynamic> json) {
    final at = json['syncedAt'];
    final types = json['types'];
    return AthenaSyncResult(
      completed: json['status']?.toString().toUpperCase() == 'COMPLETED',
      syncedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
      types: types is List
          ? types
              .whereType<Map<String, dynamic>>()
              .map(AthenaTypeResult.fromJson)
              .toList()
          : const [],
    );
  }

  /// Records stored or refreshed across every type.
  int get storedCount => types.fold(0, (n, t) => n + t.count);

  /// Types the practice does not share with CareConnect.
  List<AthenaTypeResult> get notShared => types
      .where((t) =>
          t.outcome == AthenaTypeOutcome.notGranted ||
          t.outcome == AthenaTypeOutcome.scopeDenied)
      .toList();

  /// Types that failed this time and may work on a later refresh.
  List<AthenaTypeResult> get failed => types
      .where((t) =>
          t.outcome == AthenaTypeOutcome.failed ||
          t.outcome == AthenaTypeOutcome.rejected ||
          t.outcome == AthenaTypeOutcome.unavailable)
      .toList();
}

enum AthenaTypeOutcome {
  stored,
  empty,
  failed,
  notGranted,
  scopeDenied,
  rejected,
  unavailable,
  unknown;

  static AthenaTypeOutcome parse(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'STORED':
        return stored;
      case 'EMPTY':
        return empty;
      case 'FAILED':
        return failed;
      case 'NOT_GRANTED':
        return notGranted;
      case 'SCOPE_DENIED':
        return scopeDenied;
      case 'REJECTED':
        return rejected;
      case 'UNAVAILABLE':
        return unavailable;
      default:
        return unknown;
    }
  }
}

class AthenaTypeResult {
  final String resourceType;
  final AthenaTypeOutcome outcome;
  final int count;

  const AthenaTypeResult(
      {required this.resourceType, required this.outcome, this.count = 0});

  factory AthenaTypeResult.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    return AthenaTypeResult(
      resourceType: json['resourceType']?.toString() ?? '',
      outcome: AthenaTypeOutcome.parse(json['outcome']?.toString()),
      count: count is num ? count.toInt() : 0,
    );
  }
}

enum AthenaConnectError {
  offline,
  network,
  signedOut,
  notPatient,
  disabled,
  syncInProgress,
  notConnected,
  sourceUnavailable,
  server;

  static AthenaConnectError fromResponse(int status, String? code) {
    switch (code) {
      // The backend's answer when athenahealth is turned off (R381-D01),
      // whatever the status code.
      case 'DISABLED':
        return disabled;
      case 'SYNC_IN_PROGRESS':
        return syncInProgress;
      case 'NOT_CONNECTED':
        return notConnected;
      case 'SOURCE_UNAVAILABLE':
        return sourceUnavailable;
    }
    switch (status) {
      case 401:
        return signedOut;
      case 403:
        return notPatient;
      case 404:
        return disabled;
      case 503:
        return sourceUnavailable;
      default:
        return server;
    }
  }
}

class AthenaConnectException implements Exception {
  final AthenaConnectError error;
  const AthenaConnectException(this.error);
}
