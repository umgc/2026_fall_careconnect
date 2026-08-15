import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/env_constant.dart';
import 'telemetry_settings.dart';
import 'telemetry_guardrails.dart';
import '../../services/api_service.dart';

class Telemetry {
  // Backend base URL (configurable via Dart environment variable)
  static String get _backendBase => getBackendBaseUrl();

  // Telemetry endpoint
  static String get _devEndpoint => '$_backendBase/v1/api/dev/telemetry';

  // Cache backend enabled state so we don't call the backend on every event.
  static bool? _backendEnabledCache;
  static DateTime? _backendEnabledCacheTime;

  // Keep this short so curl flips reflect quickly.
  static const Duration _backendCacheTtl = Duration(seconds: 1);

  // One-time sync guard so we don't spam backend calls.
  static bool _forcedBackendOffThisRun = false;

  // One session ID per app run
  static String? _sessionId;

  static String _getSessionId() {
    if (_sessionId != null) return _sessionId!;

    final micros = DateTime.now().microsecondsSinceEpoch;
    _sessionId = 'session-$micros';
    return _sessionId!;
  }

  static Future<bool> _enabledLocal() async {
    final optedOut = await TelemetrySettings.isOptedOut();
    return !optedOut;
  }

  static bool _backendCacheFresh() {
    final t = _backendEnabledCacheTime;
    if (t == null) return false;
    return DateTime.now().difference(t) <= _backendCacheTtl;
  }

  static Future<bool> _enabledBackendCached() async {
    if (_backendEnabledCache != null && _backendCacheFresh()) {
      return _backendEnabledCache!;
    }
    final v = await getBackendEnabled();
    _backendEnabledCache = v;
    _backendEnabledCacheTime = DateTime.now();
    return v;
  }

  // Combined gate: local AND backend
  static Future<bool> isEnabled() async {
    final local = await _enabledLocal();
    if (!local) {
      // Best-effort sync, but only once per app run.
      if (!_forcedBackendOffThisRun) {
        _forcedBackendOffThisRun = true;
      }
      return false;
    }

    final backend = await _enabledBackendCached();
    return backend;
  }

  // ---------------------------
  // Backend toggle helpers
  // ---------------------------

  static Future<bool> getBackendEnabled() async {
    try {
      final resp = await http.get(Uri.parse('$_devEndpoint/enabled'));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        final enabled = decoded is Map ? decoded['enabled'] : null;
        return enabled == true;
      }
    } catch (e) {
      _backendEnabledCache = true;
      _backendEnabledCacheTime = DateTime.now();

      if (kDebugMode) {
        debugPrint('[telemetry] getBackendEnabled failed, failing open');
      }
      return true;
    }

    // fallback (non-200 response, etc.)
    return true;
  }

  // ---------------------------
  // Event emitter
  // ---------------------------

  static Future<void> event(String name, Map<String, Object?> props) async {
    final enabled = await isEnabled();
    if (!enabled) {
      if (kDebugMode) debugPrint('[telemetry] blocked (disabled): $name');
      return;
    }

    final sanitized = TelemetryGuardrails.sanitize(name, props);
    if (sanitized == null) {
      if (kDebugMode) debugPrint('[telemetry] dropped (guardrails): $name');
      return;
    }

    final micros = DateTime.now().microsecondsSinceEpoch;

    final payload = {
      'eventName': name,
      'sessionId': _getSessionId(),
      'traceId': 'trace-$micros',
      'spanId': 'span-${micros + 1}',
      'details': sanitized,
      'deviceInfo': {
        'uiSurface': kIsWeb ? 'web' : 'mobile',
        'platform': defaultTargetPlatform.name,
        'isWeb': kIsWeb,
        'debug': kDebugMode,
      },
    };

    try {
      final resp = await ApiService.sendTelemetryEventV3(
        payload: Map<String, dynamic>.from(payload),
      );  

      final queued = resp.headers['x-offline-queued'] == 'true';

      if (kDebugMode) {
        debugPrint(
          '[telemetry] sent: $name status=${resp.statusCode} queued=$queued',
        );
        if (resp.statusCode >= 400) {
          debugPrint('[telemetry] body=${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[telemetry] send failed: $name error=$e');
      }
    }
  }
}
