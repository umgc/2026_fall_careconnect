// Additional coverage for CaregiverDashboard
// (lib/features/dashboard/presentation/pages/caregiver_dashboard.dart):
// flat payloads carrying a nested link (and dropped id-0 rows) and the
// Analytics navigation action.
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

final _rows = [
  {
    'id': 7,
    'firstName': 'Linky',
    'lastName': 'Flat',
    'dob': '02/02/1960',
    'link': {'id': 17, 'status': 'ACTIVE'},
  },
  {
    'id': 0,
    'firstName': 'Zero',
    'lastName': 'Patient',
    'dob': '03/03/1970',
    'link': {'id': 18, 'status': 'ACTIVE'},
  },
];

Future<http.Response> _handle(http.Request r) async {
  final path = r.url.path;
  if (RegExp(r'/caregivers/\d+/patients$').hasMatch(path)) {
    return http.Response(jsonEncode(_rows), 200);
  }
  if (path.endsWith('/profile/enhanced')) {
    return http.Response(jsonEncode({'data': null}), 200);
  }
  return http.Response('{}', 200);
}

final _client = MockClient(_handle);

Widget _app() {
  final router = GoRouter(
    initialLocation: '/dash',
    routes: [
      GoRoute(
          path: '/dash',
          builder: (_, __) => const CaregiverDashboard(caregiverId: 1)),
      GoRoute(
        path: '/analytics',
        builder: (_, s) => Scaffold(
            body: Text('analytics ${s.uri.queryParameters['patientId']}')),
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
  setUp(() {
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
    ApiService.debugSetHttpClient(_client);
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpDash(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 6000);
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
      http.runWithClient(body, () => _client);

  Finder inCard(String name, Finder matching) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
        matching: matching,
      );

  testWidgets('flat patients with a nested link render; id 0 is dropped',
      (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      expect(find.text('Linky Flat'), findsOneWidget);
      expect(find.text('Zero Patient'), findsNothing);
    });
  });

  testWidgets('Analytics opens the analytics route for a valid patient',
      (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      final ink = find
          .ancestor(
              of: inCard('Linky Flat', find.text('Analytics')).first,
              matching: find.byType(InkWell))
          .first;
      tester.widget<InkWell>(ink).onTap!();
      await settle(tester);
      expect(find.text('analytics 7'), findsOneWidget);
    });
  });
}
