// Tests for UpcomingCheckins widget
// (lib/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart)
//
// Covers: rendering, patient names, dates, View buttons, "View All Patients"
// button, "Start EV Session" button, icon, button taps with GoRouter, and
// structural properties (ElevatedButton styling, access_time icon).
//
// The widget is API-driven: it reads caregiverId from UserProvider, auth
// headers from AuthTokenManager, and GETs upcoming visits via
// ApiServiceOffline.httpClient. Mocks follow schedule_page_test.dart.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

import '../../../mock_user_provider.dart';

/// Mutable HTTP handler — OfflineQueueHttpClient delegates here after setUpAll.
late Future<http.Response> Function(http.Request) _httpHandler;

List<Map<String, dynamic>> _fixtureVisits() => [
      {
        'id': 1,
        'patientId': 101,
        'patientName': 'Sarah Johnson',
        'serviceType': 'Personal Care',
        'scheduledDate': '2024-12-28',
        'scheduledTime': '10:00:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
        'priority': 'Normal',
      },
      {
        'id': 2,
        'patientId': 102,
        'patientName': 'Robert Chen',
        'serviceType': 'Personal Care',
        'scheduledDate': '2024-12-28',
        'scheduledTime': '14:30:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
        'priority': 'Normal',
      },
      {
        'id': 3,
        'patientId': 103,
        'patientName': 'Maria Rodriguez',
        'serviceType': 'Personal Care',
        'scheduledDate': '2024-12-29',
        'scheduledTime': '09:15:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
        'priority': 'Normal',
      },
      {
        'id': 4,
        'patientId': 104,
        'patientName': 'David Thompson',
        'serviceType': 'Personal Care',
        'scheduledDate': '2024-12-29',
        'scheduledTime': '11:45:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
        'priority': 'Normal',
      },
    ];

Future<http.Response> _defaultHandler(http.Request request) async {
  if (request.url.path.contains('scheduled-visits/caregiver/') &&
      request.url.path.contains('/upcoming')) {
    return http.Response(jsonEncode(_fixtureVisits()), 200);
  }
  return http.Response(jsonEncode([]), 200);
}

void _setupMethodChannels() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') {
        return <String, String>{'jwt_token': 'mock-jwt-for-test'};
      }
      if (call.method == 'read') {
        final key = (call.arguments as Map?)?['key'] as String?;
        if (key == 'jwt_token') return 'mock-jwt-for-test';
        return null;
      }
      if (call.method == 'containsKey') {
        final key = (call.arguments as Map?)?['key'] as String?;
        if (key == 'jwt_token') return true;
        return false;
      }
      if (call.method == 'write' || call.method == 'delete') return null;
      return null;
    },
  );
}

void _teardownMethodChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
}

MockUserProvider _caregiverProvider() => MockUserProvider(
      mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 42),
    );

/// Wraps [child] in Provider + MaterialApp for pure rendering tests.
Widget _wrap(Widget child) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: _caregiverProvider(),
    child: MaterialApp(
      locale: const Locale('en'), 
      localizationsDelegates: AppLocalizations.localizationsDelegates, 
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// Wraps [child] in GoRouter so that context.push works without crashing.
Widget _wrapWithRouter(Widget child, {List<String> pushedRoutes = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/tasks',
        builder: (context, state) {
          pushedRoutes.add('/tasks');
          return const Scaffold(body: Text('Tasks Page'));
        },
      ),
      GoRoute(
        path: '/evv/select-patient',
        builder: (context, state) {
          pushedRoutes.add('/evv/select-patient');
          return const Scaffold(body: Text('EVV Page'));
        },
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: _caregiverProvider(),
    child: MaterialApp.router(locale: const Locale('en'), 
    localizationsDelegates: AppLocalizations.localizationsDelegates, 
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router),
  );
}

/// Advance frames so async _fetchVisits can complete (avoid pumpAndSettle
/// while CircularProgressIndicator is animating).
Future<void> _pumpPastLoading(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() {
    _httpHandler = _defaultHandler;
    final delegatingClient = MockClient((request) => _httpHandler(request));
    http.runWithClient(() {
      ApiServiceOffline.httpClient;
    }, () => delegatingClient);
  });

  setUp(() {
    _httpHandler = _defaultHandler;
    _setupMethodChannels();
  });

  tearDown(_teardownMethodChannels);

  group('UpcomingCheckins - rendering', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.byType(UpcomingCheckins), findsOneWidget);
    });

    testWidgets('shows "Upcoming Check-Ins" header text', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.text('Upcoming Check-Ins'), findsOneWidget);
    });

    testWidgets('shows calendar_today icon in header', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows all four patient names', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.text('Sarah Johnson'), findsOneWidget);
      expect(find.text('Robert Chen'), findsOneWidget);
      expect(find.text('Maria Rodriguez'), findsOneWidget);
      expect(find.text('David Thompson'), findsOneWidget);
    });

    testWidgets('shows date/time for each patient', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      // _formatDate uses "MMM d at h:mm a" for non-today/tomorrow dates
      expect(find.text('Dec 28 at 10:00 AM'), findsOneWidget);
      expect(find.text('Dec 28 at 2:30 PM'), findsOneWidget);
      expect(find.text('Dec 29 at 9:15 AM'), findsOneWidget);
      expect(find.text('Dec 29 at 11:45 AM'), findsOneWidget);
    });

    testWidgets('shows four View buttons (one per patient)', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.text('View'), findsNWidgets(4));
    });

    testWidgets('shows "View All Patients" TextButton', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.text('View All Patients'), findsOneWidget);
      final textButton = find.ancestor(
        of: find.text('View All Patients'),
        matching: find.byType(TextButton),
      );
      expect(textButton, findsOneWidget);
    });

    testWidgets('shows "Start EV Session" ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.text('Start EV Session'), findsOneWidget);
      final elevatedButton = find.ancestor(
        of: find.text('Start EV Session'),
        matching: find.byType(ElevatedButton),
      );
      expect(elevatedButton, findsOneWidget);
    });

    testWidgets('shows access_time icon next to "Start EV Session"',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });
  });

  group('UpcomingCheckins - structure', () {
    testWidgets('is wrapped in a Container with rounded corners',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(UpcomingCheckins),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('contains a Column as its main child', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(
        find.descendant(
          of: find.byType(UpcomingCheckins),
          matching: find.byType(Column),
        ),
        findsWidgets,
      );
    });

    testWidgets('each patient item has an Expanded column with name and date',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      await _pumpPastLoading(tester);
      expect(
        find.descendant(
          of: find.byType(UpcomingCheckins),
          matching: find.byType(Expanded),
        ),
        findsWidgets,
      );
    });
  });

  group('UpcomingCheckins - navigation', () {
    testWidgets('"View All Patients" navigates to /tasks', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(
        _wrapWithRouter(const UpcomingCheckins(), pushedRoutes: pushed),
      );
      await _pumpPastLoading(tester);

      await tester.tap(find.text('View All Patients'));
      await tester.pumpAndSettle();

      expect(pushed, contains('/tasks'));
    });

    testWidgets('"Start EV Session" navigates to /evv/select-patient',
        (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(
        _wrapWithRouter(const UpcomingCheckins(), pushedRoutes: pushed),
      );
      await _pumpPastLoading(tester);

      await tester.tap(find.text('Start EV Session'));
      await tester.pumpAndSettle();

      expect(pushed, contains('/evv/select-patient'));
    });

    testWidgets('View button can be tapped without error', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const UpcomingCheckins()));
      await _pumpPastLoading(tester);

      await tester.tap(find.text('View').first);
      await tester.pump();
    });
  });
}
