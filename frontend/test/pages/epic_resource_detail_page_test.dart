import 'dart:convert';

import 'package:care_connect_app/pages/epic_resource_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Widget tests for [EpicResourceDetailPage], the Epic citation destination.
/// I3c threads the deep link's `patientUserId` through to the backend; these
/// assert that forwarding and the record / not-found rendering. The page calls
/// `EpicService.getResource` (top-level `http.get`) in initState, so the mock is
/// injected with `http.runWithClient` and secure storage is stubbed empty.
const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Drives the real async (secure-storage read + mocked HTTP) to completion;
/// a bare pumpAndSettle cannot, because the loading spinner animates forever.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('forwards patientUserId to the backend and renders the record',
      (tester) async {
    Uri? seen;
    final client = MockClient((request) async {
      seen = request.url;
      return http.Response(
        jsonEncode({
          'resourceType': 'Observation',
          'resourceId': 'obs-1',
          'title': 'Blood pressure',
          'status': 'final',
          'resource': {'resourceType': 'Observation'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: EpicResourceDetailPage(
          resourceType: 'Observation',
          resourceId: 'obs-1',
          patientUserId: 'user-7',
        ),
      ));
      await _drain(tester);
    }, () => client);

    expect(seen, isNotNull);
    expect(seen!.queryParameters['patientUserId'], 'user-7');
    expect(find.text('From Epic (MyChart)'), findsOneWidget);
    expect(find.text('Blood pressure'), findsOneWidget);
  });

  testWidgets('shows the unavailable message when the record is missing',
      (tester) async {
    final client = MockClient((request) async => http.Response('x', 404));

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: EpicResourceDetailPage(
          resourceType: 'Observation',
          resourceId: 'missing',
        ),
      ));
      await _drain(tester);
    }, () => client);

    expect(find.textContaining('no longer available'), findsOneWidget);
  });
}
