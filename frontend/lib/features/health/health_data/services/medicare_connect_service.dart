import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../../services/api_service.dart';
import '../../../../config/env_constant.dart';

/// Client for the Medicare (Blue Button) connect flow.
///
/// Contract (Quinton, fix/e-ehr-api-linking, WBS 6.2.39):
///   1. GET  /v1/api/medicare/connect-url  (authenticated) -> { "url": "..." }
///      The url carries a short-lived, single-use link token that tells the
///      backend WHICH user started the flow. A browser navigation can't send
///      our JWT, which is why the old direct /oauth2/authorization/bluebutton
///      launch came back 401 / "forgot I logged in".
///   2. Open that url. The patient signs in at Medicare and approves.
///   3. The backend sends the browser back to the frontend with
///      ?medicare=connected|cancelled|failed|link_expired|already_linked
///      (it returns to the plain frontend base URL; the "/" route forwards it)
///      The link token lasts 15 minutes. already_linked means the Medicare
///      account is linked to a DIFFERENT CareConnect patient.
///   GET  /v1/api/medicare/status     -> { connected, status: LINKED|UNLINKED, connectedAt }
///   POST /v1/api/medicare/disconnect
class MedicareConnectService {
  MedicareConnectService();

  /// Swap in a fake for widget tests.
  static MedicareConnectService instance = MedicareConnectService();

  static String get _base => '${getBackendBaseUrl()}/v1/api/medicare';

  /// True when the device has no network connection. Replaceable in tests.
  static Future<bool> Function() isOffline = () async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false; // Unknown: let the request decide.
    }
  };

  /// Step 1 + 2: fetch the one-time link, then open it.
  /// Throws [MedicareConnectException] if the link can't be fetched or opened.
  /// With no network nothing is requested (FR-MCR-26).
  Future<void> connect() async {
    if (await isOffline()) {
      throw const MedicareConnectException(MedicareConnectError.offline);
    }
    final url = await fetchConnectUrl();
    final ok = await launchUrl(
      url,
      // Web: same tab, so the backend's redirect lands back in the app.
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
    if (!ok) throw const MedicareConnectException(MedicareConnectError.launch);
  }

  Future<Uri> fetchConnectUrl() async {
    final http.Response resp;
    try {
      final headers = await ApiService.getAuthHeaders();
      resp = await http.get(Uri.parse('$_base/connect-url'), headers: headers);
    } catch (_) {
      throw const MedicareConnectException(MedicareConnectError.network);
    }
    if (resp.statusCode == 401) {
      throw const MedicareConnectException(MedicareConnectError.signedOut);
    }
    if (resp.statusCode == 403) {
      // Backend: only a patient can link their own Medicare account.
      throw const MedicareConnectException(MedicareConnectError.notPatient);
    }
    if (resp.statusCode != 200) {
      throw const MedicareConnectException(MedicareConnectError.server);
    }
    try {
      final body = jsonDecode(resp.body);
      final url = body is Map ? body['url'] : null;
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null || !uri.hasScheme) throw const FormatException();
      return uri;
    } catch (_) {
      throw const MedicareConnectException(MedicareConnectError.server);
    }
  }

  /// Returns null when the status can't be checked (network/server error).
  /// The tile shows "couldn't check" in that case instead of pretending the
  /// patient isn't connected.
  Future<MedicareStatus?> status() async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final resp =
          await http.get(Uri.parse('$_base/status'), headers: headers);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      return body is Map<String, dynamic> ? MedicareStatus.fromJson(body) : null;
    } catch (_) {
      return null;
    }
  }

  /// True when the backend confirms the disconnect.
  Future<bool> disconnect() async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final resp =
          await http.post(Uri.parse('$_base/disconnect'), headers: headers);
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}

class MedicareStatus {
  final bool connected;
  final DateTime? connectedAt;

  const MedicareStatus({required this.connected, this.connectedAt});

  factory MedicareStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString().toUpperCase();
    final at = json['connectedAt'];
    return MedicareStatus(
      // Trust either field; LINKED is the backend's canonical word.
      connected: json['connected'] == true || status == 'LINKED',
      connectedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

enum MedicareConnectError { offline, network, signedOut, notPatient, server, launch }

class MedicareConnectException implements Exception {
  final MedicareConnectError error;
  const MedicareConnectException(this.error);
}

/// What the backend reported when the browser came back (?medicare=...).
enum MedicareConnectResult {
  connected,
  cancelled,
  failed,
  linkExpired,
  alreadyLinked;

  /// Unknown or missing values return null and are ignored.
  static MedicareConnectResult? parse(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'connected':
        return MedicareConnectResult.connected;
      case 'cancelled':
      case 'canceled':
        return MedicareConnectResult.cancelled;
      case 'failed':
        return MedicareConnectResult.failed;
      case 'link_expired':
        return MedicareConnectResult.linkExpired;
      case 'already_linked':
        return MedicareConnectResult.alreadyLinked;
      default:
        return null;
    }
  }
}
