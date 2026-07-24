// Tests for RecentCheckInsWidget from
// lib/features/dashboard/patient_dashboard/widgets/recent_checkin_widget.dart.
// Pure StatelessWidget with checkIns list param.
// "Open Check-In" navigates to /virtual-checkin via GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/recent_checkin_widget.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

Widget _wrap({
  List<CheckIn> checkIns = const [],
  List<String>? pushedRoutes,
}) {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 1),
  );
  final routes = pushedRoutes;

  if (routes != null) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: RecentCheckInsWidget(checkIns: checkIns),
          ),
        ),
        GoRoute(
          path: '/virtual-checkin',
          builder: (context, state) {
            routes.add('/virtual-checkin');
            return const Scaffold(body: Text('Virtual Check-In Page'));
          },
        ),
      ],
    );
    return ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: Scaffold(
        body: RecentCheckInsWidget(checkIns: checkIns),
      ),
    ),
  );
}

void main() {
  group('RecentCheckInsWidget – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(RecentCheckInsWidget), findsOneWidget);
    });

    testWidgets('shows Recent Check-Ins heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Recent Check-Ins'), findsOneWidget);
    });

    testWidgets('shows Open Check-In button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Open Check-In'), findsOneWidget);
    });

    testWidgets('renders with empty list without crashing', (tester) async {
      await tester.pumpWidget(_wrap(checkIns: []));
      expect(find.byType(RecentCheckInsWidget), findsOneWidget);
    });

    testWidgets('shows show_chart icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.show_chart), findsOneWidget);
    });

    testWidgets('shows check_circle_outline icon on button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('RecentCheckInsWidget – with check-in data', () {
    final sampleCheckIns = [
      CheckIn(date: DateTime(2026, 3, 10), status: 'Feeling good', emoji: '😊'),
      CheckIn(date: DateTime(2026, 2, 15), status: 'A bit tired', emoji: '😴'),
      CheckIn(date: DateTime(2026, 1, 5), status: 'Great day', emoji: '🎉'),
    ];

    testWidgets('shows check-in emojis', (tester) async {
      await tester.pumpWidget(_wrap(checkIns: sampleCheckIns));
      expect(find.text('😊'), findsOneWidget);
      expect(find.text('😴'), findsOneWidget);
      expect(find.text('🎉'), findsOneWidget);
    });

    testWidgets('shows check-in statuses', (tester) async {
      await tester.pumpWidget(_wrap(checkIns: sampleCheckIns));
      expect(find.text('Feeling good'), findsOneWidget);
      expect(find.text('A bit tired'), findsOneWidget);
      expect(find.text('Great day'), findsOneWidget);
    });

    testWidgets('shows formatted dates', (tester) async {
      await tester.pumpWidget(_wrap(checkIns: sampleCheckIns));
      expect(find.text('Mar 10'), findsOneWidget);
      expect(find.text('Feb 15'), findsOneWidget);
      expect(find.text('Jan 5'), findsOneWidget);
    });

    testWidgets('only shows at most 3 check-ins', (tester) async {
      final fourCheckIns = [
        ...sampleCheckIns,
        CheckIn(date: DateTime(2025, 12, 25), status: 'Holiday', emoji: '🎄'),
      ];
      await tester.pumpWidget(_wrap(checkIns: fourCheckIns));
      expect(find.text('Holiday'), findsNothing);
      expect(find.text('🎄'), findsNothing);
    });

    testWidgets('updates totalCheckIns counter', (tester) async {
      RecentCheckInsWidget.totalCheckIns = 0;
      await tester.pumpWidget(_wrap(checkIns: sampleCheckIns));
      expect(RecentCheckInsWidget.totalCheckIns, 3);
    });
  });

  group('CheckIn model', () {
    test('constructs with required fields', () {
      final checkIn = CheckIn(
        date: DateTime(2026, 6, 15),
        status: 'OK',
        emoji: '👍',
      );
      expect(checkIn.date, DateTime(2026, 6, 15));
      expect(checkIn.status, 'OK');
      expect(checkIn.emoji, '👍');
    });

    test('fromJson parses correctly', () {
      final checkIn = CheckIn.fromJson({
        'date': '2026-03-10T00:00:00.000',
        'status': 'Good',
        'emoji': '😊',
      });
      expect(checkIn.date.year, 2026);
      expect(checkIn.date.month, 3);
      expect(checkIn.date.day, 10);
      expect(checkIn.status, 'Good');
      expect(checkIn.emoji, '😊');
    });

    test('fromJson defaults status to empty string when null', () {
      final checkIn = CheckIn.fromJson({
        'date': '2026-01-01',
        'status': null,
        'emoji': '😊',
      });
      expect(checkIn.status, '');
    });

    test('fromJson defaults emoji to empty string when null', () {
      final checkIn = CheckIn.fromJson({
        'date': '2026-01-01',
        'status': 'OK',
        'emoji': null,
      });
      expect(checkIn.emoji, '');
    });

    test('fromJson defaults both to empty when missing', () {
      final checkIn = CheckIn.fromJson({
        'date': '2026-01-01',
      });
      expect(checkIn.status, '');
      expect(checkIn.emoji, '');
    });
  });

  group('RecentCheckInsWidget – static methods', () {
    test('updateCheckInCount sets totalCheckIns', () {
      RecentCheckInsWidget.updateCheckInCount([
        CheckIn(date: DateTime.now(), status: 'A', emoji: '😊'),
        CheckIn(date: DateTime.now(), status: 'B', emoji: '😊'),
      ]);
      expect(RecentCheckInsWidget.totalCheckIns, 2);
    });

    test('updateCheckInCount with empty list sets zero', () {
      RecentCheckInsWidget.updateCheckInCount([]);
      expect(RecentCheckInsWidget.totalCheckIns, 0);
    });
  });

  group('RecentCheckInsWidget – date formatting', () {
    testWidgets('formats all months correctly', (tester) async {
      final monthCheckIns = [
        CheckIn(date: DateTime(2026, 4, 1), status: 'Apr', emoji: '📅'),
        CheckIn(date: DateTime(2026, 7, 20), status: 'Jul', emoji: '📅'),
        CheckIn(date: DateTime(2026, 12, 31), status: 'Dec', emoji: '📅'),
      ];
      await tester.pumpWidget(_wrap(checkIns: monthCheckIns));
      expect(find.text('Apr 1'), findsOneWidget);
      expect(find.text('Jul 20'), findsOneWidget);
      expect(find.text('Dec 31'), findsOneWidget);
    });
  });

  group('RecentCheckInsWidget – Open Check-In navigation', () {
    testWidgets('tapping Open Check-In navigates to /virtual-checkin',
        (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(_wrap(pushedRoutes: pushed));
      await tester.tap(find.text('Open Check-In'));
      await tester.pumpAndSettle();
      expect(pushed, contains('/virtual-checkin'));
      expect(find.text('Virtual Check-In Page'), findsOneWidget);
    });
  });
}
