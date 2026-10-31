// Coverage tests for VisitInProgressPage and VisitCompletePage
// (lib/features/evv/presentation/pages/visit_in_progress_page.dart,
// lib/features/evv/presentation/pages/visit_complete_page.dart): patient
// payloads nested under a "patient" key (including malformed rows that are
// skipped), the back arrow, and check-out carrying the optional accuracy,
// no-GPS reason and scheduled visit query parameters.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/evv/presentation/pages/visit_complete_page.dart';
import 'package:care_connect_app/features/evv/presentation/pages/visit_in_progress_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

final String _nestedPatients = jsonEncode([
  'not-a-map',
  {'patient': 'not-a-map-either', 'id': 5, 'firstName': 'Skip'},
  {
    'link': 1,
    'patient': {
      'id': 42,
      'firstName': 'Nora',
      'lastName': 'Nested',
      'email': 'nora@example.com',
      'phone': '555-0101',
      'dob': '1940-02-02',
      'address': {
        'line1': '9 Elm St',
        'city': 'Norfolk',
        'state': 'VA',
        'zip': '23510',
      },
    },
  },
]);

Widget _host(Widget page) {
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
        routes: [GoRoute(path: 'visit', builder: (_, __) => page)],
      ),
      GoRoute(
        path: '/evv/checkout-location',
        builder: (_, s) => Scaffold(body: Text('CHECKOUT ${s.uri.query}')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _open(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(page));
  await tester.pump();
  GoRouter.of(tester.element(find.text('HOME'))).push('/home/visit');
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

VisitInProgressPage _inProgress() => const VisitInProgressPage(
      patientId: 42,
      serviceType: 'Personal Care',
      locationType: 'gps',
      latitude: 38.9,
      longitude: -77.0,
      accuracyM: 12.5,
      noGpsReason: 'indoors',
      scheduledVisitId: 77,
    );

VisitCompletePage _complete() => const VisitCompletePage(
      patientId: 42,
      serviceType: 'Personal Care',
      checkinLocationType: 'gps',
      checkoutLocationType: 'gps',
      checkinLatitude: 38.9,
      checkinLongitude: -77.0,
      checkoutLatitude: 38.9,
      checkoutLongitude: -77.0,
      notes: 'ok',
      duration: 600,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_nestedPatients, 200)));
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, null);
    m.setMockMethodCallHandler(_connectivity, null);
    ApiService.debugResetHttpClient();
  });

  group('VisitInProgressPage', () {
    testWidgets('finds a nested patient and skips malformed rows',
        (tester) async {
      await _open(tester, _inProgress());
      expect(find.text('Visit in Progress'), findsWidgets);
      expect(find.textContaining('Nora'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('check-out carries the optional GPS and visit parameters',
        (tester) async {
      await _open(tester, _inProgress());
      final button = find.text('Ready to Check Out');
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((d) => d.startsWith('CHECKOUT'));
      expect(text, contains('checkinAccuracyM=12.5'));
      expect(text, contains('checkinNoGpsReason=indoors'));
      expect(text, contains('scheduledVisitId=77'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('back arrow returns to the previous page', (tester) async {
      await _open(tester, _inProgress());
      await tester.tap(find.byIcon(Icons.arrow_back));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('VisitCompletePage', () {
    testWidgets('finds a nested patient and skips malformed rows',
        (tester) async {
      await _open(tester, _complete());
      expect(find.text('Visit Complete'), findsOneWidget);
      expect(find.textContaining('Nora'), findsWidgets);
    });

    testWidgets('back arrow returns to the previous page', (tester) async {
      await _open(tester, _complete());
      await tester.tap(find.byIcon(Icons.arrow_back));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
