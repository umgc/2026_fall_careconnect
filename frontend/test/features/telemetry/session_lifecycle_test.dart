// Tests for session_start and session_end telemetry in CareConnectApp.
//
// Follows telemetry_test.dart capture patterns with minimal app providers.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/main.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

Future<List<Map<String, dynamic>>> _pumpAppAndCaptureEvents(
  WidgetTester tester, {
  Future<void> Function()? afterPump,
}) async {
  final bodies = <String>[];
  final mock = MockClient((req) async {
    if (req.method == 'POST' &&
        req.url.path.contains('telemetry') &&
        !req.url.path.contains('enabled')) {
      bodies.add(req.body);
    }
    if (req.method == 'GET' && req.url.path.contains('/test/health')) {
      return http.Response(jsonEncode({'status': 'healthy'}), 200);
    }
    return http.Response(jsonEncode({'enabled': true}), 200);
  });

  ApiService.debugSetHttpClient(mock);
  try {
    await http.runWithClient(
      () async {
        await Telemetry.setBackendEnabled(true);

        final themeProvider = ThemeProvider();
        final localeProvider = LocaleProvider();
        await localeProvider.loadSaved();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: themeProvider),
              ChangeNotifierProvider.value(value: localeProvider),
            ],
            child: const CareConnectApp(),
          ),
        );
        await tester.pump();

        if (afterPump != null) {
          await afterPump();
        }

        await tester.pump(const Duration(milliseconds: 100));
        // WelcomePage schedules a 2s delay; flush it before test teardown.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
      },
      () => mock,
    );
  } finally {
    ApiService.debugResetHttpClient();
  }

  return bodies
      .map((body) => jsonDecode(body) as Map<String, dynamic>)
      .toList();
}

List<Map<String, dynamic>> _eventsNamed(
  List<Map<String, dynamic>> events,
  String name,
) {
  return events.where((event) => event['eventName'] == name).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': false});
  });

  group('CareConnectApp session lifecycle telemetry', () {
    testWidgets('emits session_start on init', (tester) async {
      final events = await _pumpAppAndCaptureEvents(tester);

      final starts = _eventsNamed(events, 'session_start');
      expect(starts, isNotEmpty);
      expect(starts.first['details']['source'], 'cold_start');
    });

    testWidgets('emits session_end when lifecycle becomes detached',
        (tester) async {
      final events = await _pumpAppAndCaptureEvents(
        tester,
        afterPump: () async {
          WidgetsBinding.instance.handleAppLifecycleStateChanged(
            AppLifecycleState.detached,
          );
        },
      );

      final ends = _eventsNamed(events, 'session_end');
      expect(ends, isNotEmpty);
      expect(ends.first['details']['reason'], 'detached');
    });
  });
}
