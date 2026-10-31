// Coverage tests for EvvRecordReviewPage EDI export
// (lib/features/evv/presentation/pages/evv_record_review.dart) with the file
// plugins mocked: no external storage on the host, so the export writes a
// temp file and opens the share sheet, then reports success.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/evv/presentation/pages/evv_record_review.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

Map<String, dynamic> _record(int id, Map<String, dynamic>? patient,
        {String name = 'Jane Q Public'}) =>
    {
      'id': id,
      if (patient != null) 'patient': patient,
      'serviceType': 'Respite Care',
      'individualName': name,
      'caregiverId': 4,
      'dateOfService': '2026-03-10T00:00:00',
      'timeIn': '2026-03-10T08:00:00',
      'timeOut': '2026-03-10T09:05:00',
      'status': 'UNDER_REVIEW',
      'stateCode': 'VA',
      'createdAt': '2026-03-10T10:00:00',
      'updatedAt': '2026-03-10T10:00:00',
    };

final _client = MockClient((r) async => http.Response(
      jsonEncode({
        'content': [
          _record(1, {
            'id': 77,
            'firstName': 'Jane',
            'lastName': 'Public',
            'dob': '1950-04-05',
            'gender': 'Male',
            'maNumber': 'MA-77',
            'address': {
              'line1': '9 Pine Rd',
              'city': 'Norfolk',
              'state': 'VA',
              'zip': '23501',
            },
          }),
          _record(2, {'id': 78, 'dob': 'not-a-date', 'gender': 'F'},
              name: 'Mononym'),
          _record(3, null, name: 'No Patient'),
        ],
        'totalElements': 3,
        'totalPages': 1,
        'size': 1000,
        'number': 0,
        'first': true,
        'last': true,
      }),
      200,
    ));

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'ADMIN', caregiverId: 4),
      ),
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const EvvRecordReviewPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _export(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  // The export touches the real file system before failing over to the
  // (absent) path_provider plugin, so let real async work complete.
  await tester.tap(find.text('Export EDI'));
  await tester.pump();
  final done = find.textContaining('export');
  for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _share = MethodChannel('dev.fluttercommunity.plus/share');
late Directory _tmp;
final List<MethodCall> _shareCalls = [];

void main() {
  setUpAll(() {
    ApiServiceOffline.debugOverrideHttpClient(_client);
    _tmp = Directory.systemTemp.createTempSync('evv_review_cov');
  });
  tearDownAll(() {
    ApiServiceOffline.debugOverrideHttpClient(null);
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_pathProvider, null);
    m.setMockMethodCallHandler(_share, null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _shareCalls.clear();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_pathProvider, (call) async => _tmp.path);
    m.setMockMethodCallHandler(_share, (call) async {
      _shareCalls.add(call);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  testWidgets('export falls back to a shared temp file and succeeds',
      (tester) async {
    await _pump(tester);
    await _export(tester, 'Jane Q Public');
    expect(_shareCalls, isNotEmpty);
    expect(
        _tmp.listSync().whereType<File>().any((f) => f.path.endsWith('.edi')),
        isTrue);
    expect(find.text('EDI document exported successfully'), findsOneWidget);
  });
}
