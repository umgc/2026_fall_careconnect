// Gap-coverage tests for CaregiverDashboard (presentation/pages): analytics and
// card navigation, id filtering, and the empty "Add Patient" state.
// All HTTP goes through the ApiService MockClient seam.
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/presentation/pages/caregiver_dashboard.dart';
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

import '../../../../mock_user_provider.dart';

bool _emptyList = false;

Future<http.Response> _handle(http.Request r) async {
  final path = r.url.path;
  if (RegExp(r'/caregivers/\d+/patients$').hasMatch(path)) {
    if (_emptyList) return http.Response('[]', 200);
    return http.Response(
      jsonEncode([
        {
          'patient': {'id': 7, 'firstName': 'Valid', 'lastName': 'Person'},
          'link': {'id': 21, 'status': 'ACTIVE'},
        },
        {
          'patient': {'id': 0, 'firstName': 'Zero', 'lastName': 'Id'},
          'link': {'id': 22, 'status': 'ACTIVE'},
        },
      ]),
      200,
    );
  }
  return http.Response('{"data": null}', 200);
}

Widget _app() {
  final router = GoRouter(
    initialLocation: '/dash',
    routes: [
      GoRoute(
        path: '/dash',
        builder: (_, __) => const CaregiverDashboard(caregiverId: 1),
      ),
      GoRoute(
        path: '/analytics',
        builder: (_, s) => Scaffold(
          body: Text('analytics for ${s.uri.queryParameters['patientId']}'),
        ),
      ),
      GoRoute(
        path: '/add-patient',
        builder: (_, __) => const Scaffold(body: Text('add patient page')),
      ),
      GoRoute(
        path: '/patient/:id',
        builder: (_, s) =>
            Scaffold(body: Text('patient page ${s.pathParameters['id']}')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
      mockUser: MockUser(id: 1, role: 'CAREGIVER', name: 'Casey'),
    ),
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  late MockClient client;

  setUp(() {
    _emptyList = false;
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    client = MockClient(_handle);
    ApiService.debugSetHttpClient(client);
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpDash(WidgetTester tester, {double width = 1800}) async {
    tester.view.physicalSize = Size(width, 6000);
    tester.view.devicePixelRatio = 1.0;
    final orig = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflow')) return;
      orig?.call(d);
    };
    addTearDown(() {
      FlutterError.onError = orig;
      tester.view.reset();
    });
    await tester.pumpWidget(_app());
    await settle(tester);
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) =>
      http.runWithClient(body, () => client);

  Finder cardOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

  // The action row sits in a horizontal scroller that clips off-screen
  // buttons, so invoke the button's InkWell.onTap directly.
  void pressAction(WidgetTester tester, String patient, String label) {
    final ink = find.descendant(
      of: cardOf(patient),
      matching: find.widgetWithText(InkWell, label),
    );
    tester.widget<InkWell>(ink.last).onTap!();
  }

  Finder tileOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile)).first;

  testWidgets('analytics with a valid id navigates with the patient id', (
    tester,
  ) async {
    await run(tester, () async {
      await pumpDash(tester);
      pressAction(tester, 'Valid Person', 'Analytics');
      await settle(tester);
      expect(find.text('analytics for 7'), findsOneWidget);
    });
  });

  testWidgets('a patient with a non-positive id is not listed', (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      expect(find.text('Valid Person'), findsOneWidget);
      expect(find.text('Zero Id'), findsNothing);
    });
  });

  testWidgets('tapping a card with a valid id opens the patient page', (
    tester,
  ) async {
    await run(tester, () async {
      await pumpDash(tester);
      tester.widget<ListTile>(tileOf('Valid Person')).onTap!();
      await settle(tester);
      expect(find.text('patient page 7'), findsOneWidget);
    });
  });

  testWidgets('an empty list shows the empty state and Add Patient navigates', (
    tester,
  ) async {
    await run(tester, () async {
      _emptyList = true;
      await pumpDash(tester, width: 600);
      expect(find.text('No patients yet'), findsOneWidget);
      await tester.tap(find.text('Add Patient'));
      await settle(tester);
      expect(find.text('add patient page'), findsOneWidget);
    });
  });

  testWidgets('the empty state also renders on a wide screen', (tester) async {
    await run(tester, () async {
      _emptyList = true;
      await pumpDash(tester);
      expect(find.text('No patients yet'), findsOneWidget);
      expect(find.text('Add Patient'), findsWidgets);
    });
  });
}
