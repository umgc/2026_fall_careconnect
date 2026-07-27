// Tests for caregiver dashboard pure widgets:
//   PatientStatisticsCards  (patient-stat-card.dart)
//   CareTeamPerformance     (careteam-performace-card.dart)
//   UpcomingCheckins        (upcoming-checkins-widget.dart)

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/patient-stat-card.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/careteam-performace-card.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

import '../../../mock_user_provider.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), 
    localizationsDelegates: AppLocalizations.localizationsDelegates, 
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)));

/// Mutable HTTP handler for ApiServiceOffline.httpClient (UpcomingCheckins).
late Future<http.Response> Function(http.Request) _upcomingHttpHandler;

List<Map<String, dynamic>> _upcomingFixtureVisits() => [
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

Future<http.Response> _upcomingDefaultHandler(http.Request request) async {
  if (request.url.path.contains('scheduled-visits/caregiver/') &&
      request.url.path.contains('/upcoming')) {
    return http.Response(jsonEncode(_upcomingFixtureVisits()), 200);
  }
  return http.Response(jsonEncode([]), 200);
}

void _setupUpcomingAuthChannels() {
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

void _teardownUpcomingAuthChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    null,
  );
}

Widget _wrapUpcoming(Widget child) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
      mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 42),
    ),
    child: MaterialApp(
      locale: const Locale('en'), 
      localizationsDelegates: AppLocalizations.localizationsDelegates, 
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Future<void> _pumpPastUpcomingLoading(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

// ─────────────────────────────────────────────────────────────────────────────
// PatientStatisticsCards
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  setUpAll(() {
    _upcomingHttpHandler = _upcomingDefaultHandler;
    final delegatingClient =
        MockClient((request) => _upcomingHttpHandler(request));
    http.runWithClient(() {
      ApiServiceOffline.httpClient;
    }, () => delegatingClient);
  });

  group('PatientStatisticsCards', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      expect(find.byType(PatientStatisticsCards), findsOneWidget);
    });

    testWidgets('shows missed check-ins label', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      // Large-screen layout uses '# of Missed\nCheck-Ins'; search for partial match
      expect(find.textContaining('of Missed'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows active patients label', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      // Large-screen layout uses 'Active\nPatients'; small-screen uses 'Active Patients'
      expect(find.textContaining('Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows value "24" for missed check-ins', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      expect(find.text('24'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows value "32" for active patients', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      expect(find.text('32'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows people_outline icon', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      expect(find.byIcon(Icons.people_outline), findsAtLeastNWidgets(1));
    });

    testWidgets('shows monitor_heart_outlined icon', (tester) async {
      await tester.pumpWidget(_wrap(const PatientStatisticsCards()));
      expect(find.byIcon(Icons.monitor_heart_outlined), findsAtLeastNWidgets(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CareTeamPerformance
  // ───────────────────────────────────────────────────────────────────────────
  group('CareTeamPerformance', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.byType(CareTeamPerformance), findsOneWidget);
    });

    testWidgets('shows "Care Team Performance" title', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('Care Team Performance'), findsOneWidget);
    });

    testWidgets('shows "Overall Patient Satisfaction" label', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('Overall Patient Satisfaction'), findsOneWidget);
    });

    testWidgets('shows satisfaction rating "4.8/5"', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('4.8/5'), findsOneWidget);
    });

    testWidgets('shows "Excellent" label', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shows "Check-in Completion Rate" label', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('Check-in Completion Rate'), findsOneWidget);
    });

    testWidgets('shows "89%" completion rate', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.text('89%'), findsOneWidget);
    });

    testWidgets('shows LinearProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows trending_up icon', (tester) async {
      await tester.pumpWidget(_wrap(const CareTeamPerformance()));
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // UpcomingCheckins
  // ───────────────────────────────────────────────────────────────────────────
  group('UpcomingCheckins', () {
    setUp(() {
      _upcomingHttpHandler = _upcomingDefaultHandler;
      _setupUpcomingAuthChannels();
    });

    tearDown(_teardownUpcomingAuthChannels);

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.byType(UpcomingCheckins), findsOneWidget);
    });

    testWidgets('shows "Upcoming Check-Ins" header', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.text('Upcoming Check-Ins'), findsOneWidget);
    });

    testWidgets('shows patient names', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.text('Sarah Johnson'), findsOneWidget);
      expect(find.text('Robert Chen'), findsOneWidget);
    });

    testWidgets('shows "View All Patients" button', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.text('View All Patients'), findsOneWidget);
    });

    testWidgets('shows "Start EV Session" button', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.text('Start EV Session'), findsOneWidget);
    });

    testWidgets('shows calendar_today icon', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows View buttons for each patient', (tester) async {
      await tester.pumpWidget(_wrapUpcoming(const UpcomingCheckins()));
      await _pumpPastUpcomingLoading(tester);
      // 4 patients, each has a View button
      expect(find.text('View'), findsNWidgets(4));
    });
  });
}
