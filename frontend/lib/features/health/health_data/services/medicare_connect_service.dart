import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../../services/api_service.dart';
import '../../../../config/env_constant.dart';

/// Client for the Medicare (Blue Button 2.0) connect flow.
///
/// Mirrors Team D's EpicService pattern. connect() starts the Spring OAuth
/// login for the "bluebutton" registration (PKCE), which returns via
/// /login/oauth2/code/bluebutton. status() and disconnect() are stubbed until
/// the backend builds them (WBS 6.2.39) — swap the stub bodies for real calls
/// when the endpoints land; the tile does not change.
class MedicareConnectService {
  static String get _authorizeUrl =>
      '${getBackendBaseUrl()}/oauth2/authorization/bluebutton';

  // When the backend 6.2.39 endpoints exist, point these at them.
  static String get _statusUrl => '${getBackendBaseUrl()}/api/medicare/status';
  static String get _disconnectUrl =>
      '${getBackendBaseUrl()}/api/medicare/disconnect';

  /// Start the connect flow — opens the Blue Button OAuth login in the browser.
  static Future<void> connect() async {
    await launchUrl(
      Uri.parse(_authorizeUrl),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  /// Current connection status: {connected: bool, status?, connectedAt?}.
  /// STUB: returns not-connected until the backend status endpoint exists.
  static Future<Map<String, dynamic>> status() async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final resp = await http.get(Uri.parse(_statusUrl), headers: headers);
      if (resp.statusCode != 200) return {'connected': false};
      return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    } catch (_) {
      // Endpoint not built yet — treat as not connected.
      return {'connected': false};
    }
  }

  /// Disconnect Medicare. STUB until the backend disconnect endpoint exists.
  static Future<bool> disconnect() async {
    try {
      final headers = await ApiService.getAuthHeaders();
      final resp = await http.post(Uri.parse(_disconnectUrl), headers: headers);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}