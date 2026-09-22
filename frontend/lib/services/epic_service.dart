import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import '../config/env_constant.dart';

/// Client for the Epic SMART-on-FHIR connect flow (Epic Phase 0).
///
/// Mirrors the existing Google-Health web-OAuth connect: an authenticated GET to the backend
/// returns `{authUrl}`, which is opened in an external browser. The return trip is handled by the
/// `careconnect://epic/linked` deep link (see `main.dart`).
class EpicService {
  static String get _base => '${getBackendBaseUrl()}/api/epic';

  /// Start the connect flow. Throws on a non-200 from the backend.
  static Future<void> connect() async {
    final headers = await ApiService.getAuthHeaders();
    // On web the backend must return the browser to the web app (there is no custom-scheme deep
    // link). returnMode=web makes the callback redirect to the /epic-linked web route instead of
    // the careconnect://epic/linked deep link used on Android/iOS.
    final authorizeUri = Uri.parse('$_base/authorize').replace(
      queryParameters: kIsWeb ? const {'returnMode': 'web'} : null,
    );
    final resp = await http.get(authorizeUri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Epic authorize failed (${resp.statusCode})');
    }
    final authUrl = (jsonDecode(resp.body) as Map)['authUrl'] as String;
    await launchUrl(
      Uri.parse(authUrl),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      // On web, navigate the app tab itself ('_self') to Epic so the backend can redirect the
      // SAME tab back to the /epic-linked web route on completion (returnMode=web). A separate
      // '_blank' tab does not return the user to the app, so full-page navigation is preferred.
      // Epic's login cannot be embedded in an iframe (X-Frame-Options); the fully in-app WebView
      // is the Android/iOS flow (EpicWebViewLoginPage).
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  /// Fetch the Epic authorize URL without opening it, for the in-app WebView connect flow
  /// (mobile). The default (no `returnMode`) makes the backend callback redirect to the
  /// `careconnect://epic/linked` deep link, which the WebView page intercepts. Throws on non-200.
  static Future<String> authorizeUrl() async {
    final headers = await ApiService.getAuthHeaders();
    final resp = await http.get(Uri.parse('$_base/authorize'), headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Epic authorize failed (${resp.statusCode})');
    }
    return (jsonDecode(resp.body) as Map)['authUrl'] as String;
  }

  /// Returns the current Epic connection status: `{connected: bool, status?, connectedAt?}`.
  static Future<Map<String, dynamic>> status() async {
    final headers = await ApiService.getAuthHeaders();
    final resp = await http.get(Uri.parse('$_base/status'), headers: headers);
    if (resp.statusCode != 200) {
      return {'connected': false};
    }
    return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
  }

  /// Fetch one mirrored Epic resource for the current user (Epic citation detail).
  /// Returns null on 404 / error. Scoped server-side to the caller's own records.
  static Future<Map<String, dynamic>?> getResource(String type, String id) async {
    final headers = await ApiService.getAuthHeaders();
    final resp = await http.get(
      Uri.parse('$_base/resource/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      return null;
    }
    return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
  }

  /// Disconnect Epic: deletes tokens, revokes consent, and de-indexes Epic chunks.
  static Future<bool> disconnect() async {
    final headers = await ApiService.getAuthHeaders();
    final resp = await http.post(Uri.parse('$_base/disconnect'), headers: headers);
    return resp.statusCode == 200;
  }
}
