import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/env_constant.dart';
import 'api_service.dart';

/// Connection status reported by the CareConnect backend.
class OracleHealthConnectionStatus {
  final bool connected;
  final String? status;
  final String source;

  const OracleHealthConnectionStatus({
    required this.connected,
    required this.source,
    this.status,
  });

  factory OracleHealthConnectionStatus.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['connected'] is! bool) {
      throw const FormatException(
        'Oracle Health status response is missing connected.',
      );
    }

    return OracleHealthConnectionStatus(
      connected: json['connected'] as bool,
      source: json['source'] as String? ?? 'ORACLE_HEALTH',
      status: json['status'] as String?,
    );
  }
}

/// Client for the backend-managed Oracle Health SMART connection.
class OracleHealthService {
  static String get _base => '${getBackendBaseUrl()}/api/oracle-health';

  /// Request the authorization URL without launching a browser.
  static Future<String> authorizeUrl({
    bool? webReturn,
    String? launch,
  }) async {
    if (launch != null && launch.trim().isEmpty) {
      throw ArgumentError.value(
        launch,
        'launch',
        'Oracle Health launch token cannot be empty.',
      );
    }

    final headers = await ApiService.getAuthHeaders();

    final queryParameters = <String, String>{
      if (webReturn ?? kIsWeb) 'returnMode': 'web',
      if (launch != null) 'launch': launch,
    };

    final uri = Uri.parse('$_base/authorize').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );

    final response = await http.get(uri, headers: headers);

    if (response.statusCode != 200) {
      throw Exception(
        'Oracle Health authorization failed '
        '(${response.statusCode}).',
      );
    }

    final json = (jsonDecode(response.body) as Map).cast<String, dynamic>();

    final authUrl = json['authUrl'];

    if (authUrl is! String || authUrl.isEmpty) {
      throw const FormatException(
        'Oracle Health authorization URL is missing.',
      );
    }

    final parsed = Uri.tryParse(authUrl);

    if (parsed == null || parsed.scheme != 'https') {
      throw const FormatException(
        'Oracle Health authorization URL must use HTTPS.',
      );
    }

    return authUrl;
  }

  /// Start the backend-managed SMART authorization flow.
  ///
  /// For EHR-initiated launches, pass the temporary Oracle Health
  /// launch token. Standalone connections omit it.
  static Future<void> connect({String? launch}) async {
    final url = await authorizeUrl(launch: launch);

    final launched = await launchUrl(
      Uri.parse(url),
      mode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );

    if (!launched) {
      throw Exception(
        'Unable to open Oracle Health authorization.',
      );
    }
  }

  /// Read the authenticated user's Oracle Health connection status.
  static Future<OracleHealthConnectionStatus> status() async {
    final headers = await ApiService.getAuthHeaders();

    final response = await http.get(
      Uri.parse('$_base/status'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to check Oracle Health connection '
        '(${response.statusCode}).',
      );
    }

    final json = (jsonDecode(response.body) as Map).cast<String, dynamic>();

    return OracleHealthConnectionStatus.fromJson(json);
  }

  /// Disconnect the authenticated user's Oracle Health account.
  static Future<void> disconnect() async {
    final headers = await ApiService.getAuthHeaders();

    final response = await http.post(
      Uri.parse('$_base/disconnect'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to disconnect Oracle Health '
        '(${response.statusCode}).',
      );
    }
  }
}

/// Injectable interface for Oracle Health connection operations.
abstract class OracleHealthConnectionClient {
  Future<OracleHealthConnectionStatus> status();

  Future<void> connect();

  Future<void> disconnect();
}

/// Production implementation backed by OracleHealthService.
class DefaultOracleHealthConnectionClient
    implements OracleHealthConnectionClient {
  const DefaultOracleHealthConnectionClient();

  @override
  Future<OracleHealthConnectionStatus> status() {
    return OracleHealthService.status();
  }

  @override
  Future<void> connect() {
    return OracleHealthService.connect();
  }

  @override
  Future<void> disconnect() {
    return OracleHealthService.disconnect();
  }
}
