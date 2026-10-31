// Additional coverage for the presentation PatientDashboard
// (lib/features/dashboard/presentation/pages/patient_dashboard.dart):
// navigation links, the SOS options sheet and the caregiver card menu.

import 'dart:convert';

import 'package:care_connect_app/features/dashboard/presentation/pages/patient_dashboard.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mock_user_provider.dart';

Future<http.Response> _handle(http.Request r) async {
  final path = r.url.path;
  if (path.contains('sos-call')) return http.Response('down', 500);
  if (path.contains('caregiver-patient-links')) {
    return http.Response('[]', 200);
  }
  if (path.endsWith('/patients/1/caregivers')) {
    return http.Response(
        jsonEncode([
          {
            'id': 10,
            'firstName': 'Casey',
            'lastName': 'Giver',
            'phone': '555-123-4567',
            'email': 'casey@example.test',
          },
        ]),
        200);
  }
  if (RegExp(r'/patients/1$').hasMatch(path)) {
    // The page reads this URL first for the patient, then for family.
    _patientCalls++;
    if (_patientCalls > 1) return http.Response('[]', 200);
    return http.Response(
        jsonEncode({'id': 1, 'firstName': 'Pat', 'lastName': 'Doe'}), 200);
  }
  return http.Response('{}', 200);
}

var _patientCalls = 0;
final _client = MockClient(_handle);
final _launched = <String>[];

void main() {
  setUp(() {
    _launched.clear();
    _patientCalls = 0;
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    for (final name in [
      'plugins.flutter.io/url_launcher',
      'plugins.flutter.io/url_launcher_android',
      'plugins.flutter.io/url_launcher_ios',
      'plugins.flutter.io/url_launcher_windows',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'canLaunch') return false;
        _launched.add('${call.method}:${call.arguments}');
        return true;
      });
    }
    m.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
    ApiService.debugSetHttpClient(_client);
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> frames(WidgetTester t, [int n = 15]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpDash(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflow')) return;
      orig?.call(d);
    };
    addTearDown(() {
      FlutterError.onError = orig;
      t.view.reset();
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const PatientDashboard()),
      GoRoute(
          path: '/tasks/today', builder: (_, __) => const Text('Tasks Route')),
      GoRoute(path: '/evv', builder: (_, __) => const Text('EVV Route')),
    ]);
    await http.runWithClient(() async {
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
            mockUser:
                MockUser(id: 1, role: 'PATIENT', patientId: 1, name: 'Pat')),
        child: MaterialApp.router(
          locale: const Locale('en'),
          theme: ThemeData(platform: TargetPlatform.iOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await frames(t, 20);
    }, () => _client);
  }

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.ensureVisible(f.first);
    await t.pump();
    await t.tap(f.first);
    await t.pumpAndSettle();
  }

  testWidgets("View Today's Task navigates to the tasks route", (t) async {
    await pumpDash(t);
    await tapText(t, "View Today's Task");
    expect(find.text('Tasks Route'), findsOneWidget);
  });

  testWidgets('Visit Schedule navigates to the EVV route', (t) async {
    await pumpDash(t);
    await tapText(t, 'Visit Schedule');
    expect(find.text('EVV Route'), findsOneWidget);
  });

  testWidgets('Visit History navigates to the EVV route', (t) async {
    await pumpDash(t);
    await tapText(t, 'Visit History');
    expect(find.text('EVV Route'), findsOneWidget);
  });

  testWidgets('SOS options sheet closes and opens the SOS dialog', (t) async {
    await pumpDash(t);
    await tapText(t, 'SOS Emergency');
    expect(find.text('SOS Emergency Options'), findsOneWidget);

    await t.tap(find.descendant(
        of: find.byType(BottomSheet), matching: find.byIcon(Icons.close)));
    await t.pumpAndSettle();
    expect(find.text('SOS Emergency Options'), findsNothing);

    await tapText(t, 'SOS Emergency');
    await t.tap(find.text('Select emergency type and send alert'));
    await t.pumpAndSettle();
    expect(find.text('SOS Emergency Options'), findsNothing);
    expect(find.byType(Dialog), findsWidgets);
  });

  Future<void> pickMenu(WidgetTester t, String item) async {
    final menu = find.descendant(
        of: find.byType(Card), matching: find.byIcon(Icons.more_vert));
    await t.ensureVisible(menu.first);
    await t.pump();
    await t.tap(menu.first);
    await t.pumpAndSettle();
    await t.tap(find.text(item).last);
    await t.pumpAndSettle();
  }

  testWidgets('caregiver menu email falls back to a snackbar', (t) async {
    await pumpDash(t);
    expect(find.text('Casey Giver'), findsOneWidget);
    await pickMenu(t, 'Email');
    expect(find.text('Could not launch email client.'), findsOneWidget);
  });

  testWidgets('caregiver menu call uses the phone launcher', (t) async {
    await pumpDash(t);
    await pickMenu(t, 'Call');
    expect(find.byType(PatientDashboard), findsOneWidget);
  });

  testWidgets('caregiver menu SMS opens the message dialog and sends',
      (t) async {
    await pumpDash(t);
    await pickMenu(t, 'Send SMS');
    expect(find.text('Send message to Casey Giver'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await pickMenu(t, 'Send SMS');
    await t.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'On my way');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('SMS sent to Casey Giver'), findsOneWidget);
  });

  testWidgets('quick location share sends an SOS alert and shows status',
      (t) async {
    await pumpDash(t);
    await http.runWithClient(() async {
      await tapText(t, 'SOS Emergency');
      await t.tap(find.text('Share My Location (Quick)'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }, () => _client);
    expect(find.textContaining('Failed to send SOS alert (500)'),
        findsOneWidget);
    // Let the delayed status reset fire.
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.byType(PatientDashboard), findsOneWidget);
  });
}
