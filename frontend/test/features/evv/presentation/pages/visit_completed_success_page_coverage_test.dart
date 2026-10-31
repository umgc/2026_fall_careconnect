// Coverage tests for VisitCompletedSuccessPage
// (lib/features/evv/presentation/pages/visit_completed_success_page.dart):
// patients nested under a "patient" key, minute/second duration formats, the
// narrow and dark layouts, the back arrow and Dashboard buttons, and the
// non-web EDI export (falls back to a temp file + share sheet when no
// external storage is available).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/evv/presentation/pages/visit_completed_success_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _share = MethodChannel('dev.fluttercommunity.plus/share');
const _openFile = MethodChannel('com.crazecoder.openfile');

late Directory _tmp;
final List<MethodCall> _shareCalls = [];

void _stubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  m.setMockMethodCallHandler(
      _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
  m.setMockMethodCallHandler(_pathProvider, (call) async => _tmp.path);
  m.setMockMethodCallHandler(_share, (call) async {
    _shareCalls.add(call);
    return 'dev.fluttercommunity.plus/share/unavailable';
  });
  m.setMockMethodCallHandler(_openFile,
      (call) async => '{"type":0,"message":"done"}');
}

void _clearStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final c in [_secureStorage, _connectivity, _pathProvider, _share, _openFile]) {
    m.setMockMethodCallHandler(c, null);
  }
}

String _nestedPatients() => jsonEncode([
      {'patient': 'not-a-map', 'id': 1, 'firstName': 'Bad'},
      {
        'link': 'x',
        'patient': {
          'id': 42,
          'firstName': 'Nora',
          'lastName': 'Nested',
          'email': 'nora@example.com',
          'phone': '555-0101',
          'dob': '1940-02-02',
          'maNumber': 'MA987654321',
          'address': {
            'line1': '9 Elm St',
            'line2': 'Unit 2',
            'city': 'Norfolk',
            'state': 'VA',
            'zip': '23510',
          },
        },
      },
    ]);

Widget _host({
  int duration = 90,
  ThemeData? theme,
  String checkin = 'gps',
}) {
  final provider = UserProvider()
    ..setUser(UserSession(
      id: 1,
      email: 'cg@example.com',
      role: 'CAREGIVER',
      token: 't',
      caregiverId: 1,
    ));
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
        routes: [
          GoRoute(
            path: 'success',
            builder: (_, __) => VisitCompletedSuccessPage(
              patientId: 42,
              serviceType: 'Companion Care',
              checkinLocationType: checkin,
              checkoutLocationType: 'gps',
              checkinLatitude: null,
              checkinLongitude: null,
              checkoutLatitude: 36.85,
              checkoutLongitude: -76.28,
              notes: 'All good',
              duration: duration,
              checkinTime: DateTime(2026, 8, 1, 0, 5, 0),
              checkoutTime: DateTime(2026, 8, 1, 13, 6, 30),
            ),
          ),
        ],
      ),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router, theme: theme),
  );
}

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.text('HOME'))).push('/home/success');
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('evv_success_cov');
  });

  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _shareCalls.clear();
    _stubs();
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_nestedPatients(), 200)));
  });

  tearDown(() {
    _clearStubs();
    ApiService.debugResetHttpClient();
  });

  testWidgets('nested patient payload renders with m+s duration (narrow)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _open(tester, _host(duration: 90));

    expect(find.text('Nora Nested'), findsOneWidget);
    expect(find.text('1m 30s'), findsOneWidget);
    expect(find.textContaining('GPS (coords unavailable)'), findsWidgets);
    expect(find.text('12:05:00 AM'), findsOneWidget);
    expect(find.text('1:06:30 PM'), findsOneWidget);
  });

  testWidgets('seconds-only duration renders in the dark theme',
      (tester) async {
    await _open(tester, _host(duration: 45, theme: ThemeData.dark()));
    expect(find.text('45s'), findsOneWidget);
    expect(find.text('Nora Nested'), findsOneWidget);
  });

  testWidgets('back arrow pops to the previous page', (tester) async {
    await _open(tester, _host());
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('Dashboard button goes to the caregiver dashboard',
      (tester) async {
    await _open(tester, _host());
    final button = find.widgetWithText(FilledButton, 'Dashboard');
    tester.widget<FilledButton>(button).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('Export EDI writes a temp file and opens the share sheet',
      (tester) async {
    await _open(tester, _host(checkin: 'address'));
    final exportBtn = find.widgetWithText(OutlinedButton, 'Export EDI');
    expect(exportBtn, findsOneWidget);

    await tester.runAsync(() async {
      tester.widget<OutlinedButton>(exportBtn).onPressed!();
      for (var i = 0; i < 50 && _shareCalls.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(_shareCalls, isNotEmpty);
    final written = _tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.edi'))
        .toList();
    expect(written, isNotEmpty);
    expect(written.first.readAsStringSync(), contains('ISA'));
    expect(find.text('Visit data exported successfully'), findsOneWidget);
  });
}
