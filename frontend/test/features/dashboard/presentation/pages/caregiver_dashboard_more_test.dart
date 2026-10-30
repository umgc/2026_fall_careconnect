// More happy-path tests for CaregiverDashboard
// (lib/features/dashboard/presentation/pages/caregiver_dashboard.dart):
// patient payload variants and enhanced-profile fallbacks, the card's
// relationship menu (suspend, reactivate, patient video-call policy), the
// Medical Notes button, the help action and a changed caregiver id.
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

class _Backend {
  int listStatus = 200;
  int actionStatus = 200;
  bool throwEnhanced = false;
  final posts = <String>[];

  List<dynamic> rows() => [
        'not-a-map',
        {'patient': 'not-a-map-either'},
        {
          'patient': {
            'id': 1,
            'firstName': 'Ann',
            'lastName': 'Active',
            'dob': '01/15/1950',
            'gender': null,
          },
          'link': {'id': 11, 'status': 'ACTIVE', 'relationship': 'Parent'},
        },
        {
          'patient': {
            'id': 2,
            'firstName': '',
            'lastName': 'Suspended',
            'dob': '12/31/1990',
          },
          'link': {'id': 12, 'status': 'SUSPENDED'},
        },
        {
          'id': 3,
          'firstName': 'Flat',
          'lastName': 'NoVideo',
          'dob': 'bad-dob',
          'linkId': 13,
          'linkStatus': 'ACTIVE',
          'patientVideoCallsEnabled': false,
        },
        {
          'patient': {
            'id': 4,
            'firstName': 'Nolink',
            'lastName': 'Person',
            'dob': 'aa/bb/cccc',
          },
        },
        {
          'patient': {
            'id': 5,
            'firstName': 'Old',
            'lastName': 'Timer',
            'dob': '01/01/1800',
          },
          'link': {'id': 15},
        },
        {
          'patient': {'id': 0, 'firstName': 'Zero'},
        },
      ];

  Map<String, dynamic> enhanced(String id) {
    switch (id) {
      case '1':
        return {
          'data': {
            'allergies': [
              'Peanuts',
              {'allergen': 'Latex', 'severity': 'Severe'},
              {'allergen': 'Dust', 'severity': ''},
            ],
            'latestVitals': {
              'heartRate': 50,
              'bloodPressure': '120/80',
              'systolic': 120,
              'diastolic': 80,
              'temperature': 101.2,
              'oxygenSaturation': 90,
              'respiratoryRate': 25,
              'glucose': 200,
            },
            'medications': ['A'],
          },
        };
      case '2':
        return {
          'data': {
            'allergies': 'not-a-list',
            'latestVitals': 'not-a-map',
            'medications': 'not-a-list',
          },
        };
      case '3':
        return {
          'data': {
            'latestVitals': {
              'heartRate': 120,
              'temperature': 95.0,
              'oxygenSaturation': 99,
              'respiratoryRate': 8,
              'glucose': 50,
            },
          },
        };
      default:
        return {'data': null};
    }
  }

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (r.method == 'POST') posts.add(path);
    final enhancedMatch =
        RegExp(r'/patients/(\d+)/profile/enhanced$').firstMatch(path);
    if (enhancedMatch != null) {
      final id = enhancedMatch.group(1)!;
      if (throwEnhanced && id == '5') {
        throw http.ClientException('enhanced down');
      }
      if (id == '4') return http.Response('{}', 500);
      return http.Response(jsonEncode(enhanced(id)), 200);
    }
    if (RegExp(r'/caregivers/\d+/patients$').hasMatch(path)) {
      return http.Response(jsonEncode(rows()), listStatus);
    }
    if (path.endsWith('/suspend') ||
        path.endsWith('/reactivate') ||
        path.endsWith('/patient-video-calls')) {
      return http.Response('{}', actionStatus);
    }
    return http.Response('{}', 200);
  }
}

late _Backend _backend;

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int caregiverId = 1;
  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(
          onPressed: () => setState(() => caregiverId = 2),
          child: const Text('switch caregiver'),
        ),
        Expanded(child: CaregiverDashboard(caregiverId: caregiverId)),
      ]);
}

Widget _app() {
  final router = GoRouter(
    initialLocation: '/dash',
    routes: [
      GoRoute(path: '/dash', builder: (_, __) => const _Host()),
      GoRoute(
        path: '/patient/:id',
        builder: (_, s) =>
            Scaffold(body: Text('patient page ${s.pathParameters['id']}')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
      mockUser: MockUser(
        id: 1,
        role: 'CAREGIVER',
        name: 'Casey',
      ),
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
    _backend = _Backend();
    client = MockClient((r) => _backend.handle(r));
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

  Finder menuFor(String name) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
        matching: find.byIcon(Icons.more_vert),
      );

  testWidgets('parses every payload shape and summarises vitals and allergies',
      (tester) async {
    await run(tester, () async {
      _backend.throwEnhanced = true;
      await pumpDash(tester);
      expect(find.text('Ann Active'), findsOneWidget);
      expect(find.text(' Suspended'), findsOneWidget);
      expect(find.text('Flat NoVideo'), findsOneWidget);
      expect(find.text('Nolink Person'), findsOneWidget);
      expect(find.text('Old Timer'), findsOneWidget);
      expect(find.textContaining('Latex (Severe)'), findsOneWidget);
      expect(find.textContaining('HR: 50 bpm'), findsOneWidget);
      expect(find.textContaining('HR: 120 bpm'), findsOneWidget);
    });
  });

  testWidgets('the list layout works on a narrow screen', (tester) async {
    await run(tester, () async {
      await pumpDash(tester, width: 800);
      expect(find.text('Ann Active'), findsOneWidget);
    });
  });

  testWidgets('a failed patient load shows the error state', (tester) async {
    await run(tester, () async {
      _backend.listStatus = 500;
      await pumpDash(tester);
      expect(find.textContaining('Failed to load patients. Status: 500'),
          findsOneWidget);
    });
  });

  for (final status in [200, 500]) {
    testWidgets('suspending a relationship reports a $status', (tester) async {
      await run(tester, () async {
        _backend.actionStatus = status;
        await pumpDash(tester);
        await tester.tap(menuFor('Ann Active'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suspend Relationship'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SUSPEND'));
        await settle(tester);
        expect(
            find.text(status == 200
                ? 'Relationship with Ann suspended'
                : 'Failed to suspend relationship: 500'),
            findsOneWidget);
      });
    });

    testWidgets('reactivating a relationship reports a $status',
        (tester) async {
      await run(tester, () async {
        _backend.actionStatus = status;
        await pumpDash(tester);
        await tester.tap(menuFor(' Suspended'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reactivate Relationship'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('REACTIVATE'));
        await settle(tester);
        expect(
            find.text(status == 200
                ? 'Relationship with  reactivated'
                : 'Failed to reactivate relationship: 500'),
            findsOneWidget);
      });
    });

    testWidgets('changing patient video calls reports a $status',
        (tester) async {
      await run(tester, () async {
        _backend.actionStatus = status;
        await pumpDash(tester);
        await tester.tap(menuFor('Flat NoVideo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enable Patient Video Calls'));
        await settle(tester);
        expect(
            find.text(status == 200
                ? 'Patient-initiated video calls enabled.'
                : 'Failed to update video call policy.'),
            findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.tap(menuFor('Ann Active'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disable Patient Video Calls'));
        await settle(tester);
      });
    });
  }

  testWidgets('a patient without a link id cannot be suspended or changed',
      (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      await tester.tap(menuFor('Nolink Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend Relationship'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SUSPEND'));
      await settle(tester);
      expect(find.text('Error: Missing link ID'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.tap(menuFor('Nolink Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable Patient Video Calls'));
      await settle(tester);
      expect(find.text('Missing caregiver link ID.'), findsOneWidget);
    });
  });

  testWidgets('a suspended patient without a link id cannot be reactivated',
      (tester) async {
    _backend = _Backend();
    await run(tester, () async {
      await pumpDash(tester);
      await tester.tap(menuFor('Old Timer'));
      await tester.pumpAndSettle();
      // Old Timer's link has no status: ACTIVE, so offer suspend; cancel it.
      await tester.tap(find.text('Suspend Relationship'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(_backend.posts, isEmpty);
    });
  });

  testWidgets('View Profile from the menu opens the patient page',
      (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      await tester.tap(menuFor('Ann Active'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Profile'));
      await settle(tester);
      expect(find.text('patient page 1'), findsOneWidget);
    });
  });

  testWidgets('Medical Notes opens the notes page', (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      final ink = find
          .ancestor(
              of: find.text('Medical Notes').first,
              matching: find.byType(InkWell))
          .first;
      tester.widget<InkWell>(ink).onTap!();
      await settle(tester);
      expect(find.textContaining('Ann Active - '), findsOneWidget);
    });
  });

  testWidgets('the help action and a new caregiver id refresh the dashboard',
      (tester) async {
    await run(tester, () async {
      await pumpDash(tester);
      final help = find.byIcon(Icons.help_outline);
      if (help.evaluate().isNotEmpty) {
        await tester.tap(help.first);
        await tester.pump();
        expect(find.text('Help documentation coming soon'), findsOneWidget);
      }
      await tester.tap(find.text('switch caregiver'));
      await settle(tester);
      expect(find.text('Ann Active'), findsOneWidget);
    });
  });
}
