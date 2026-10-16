// Tests for VirtualCheckInHistoryCard widget
// (lib/features/health/virtual_check_in/presentation/widgets/virtual_check_in_history_card.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_history_card.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

VirtualCheckIn _entry({
  String id = '1',
  CheckInType type = CheckInType.routine,
  String clinicianName = 'Dr. Smith',
  CheckInStatus status = CheckInStatus.completed,
  String moodLabel = 'Good',
  String summary = 'Patient doing well.',
  int durationMinutes = 20,
}) =>
    VirtualCheckIn(
      id: id,
      type: type,
      clinicianName: clinicianName,
      startedAt: DateTime(2024, 6, 1, 10, 30),
      durationMinutes: durationMinutes,
      status: status,
      moodLabel: moodLabel,
      nextCheckIn: DateTime(2024, 6, 8),
      summary: summary,
    );

void main() {
  group('VirtualCheckInHistoryCard', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(entries: [])));
      expect(find.byType(VirtualCheckInHistoryCard), findsOneWidget);
    });

    testWidgets('shows Virtual Check-In History header', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(entries: [])));
      expect(find.text('Virtual Check-In History'), findsOneWidget);
    });

    testWidgets('shows empty state when entries is empty', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(entries: [])));
      expect(find.text('No virtual check-ins yet'), findsOneWidget);
    });

    testWidgets('shows computer icon in header', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(entries: [])));
      expect(find.byIcon(Icons.computer), findsOneWidget);
    });

    testWidgets('does not show Configure button when showConfigure=false', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [],
        showConfigure: false,
      )));
      expect(find.text('Configure Patient Check-in'), findsNothing);
    });

    testWidgets('shows Configure button when showConfigure=true', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [],
        showConfigure: true,
        onConfigure: () {},
      )));
      expect(find.text('Configure Patient Check-in'), findsOneWidget);
    });

    testWidgets('shows clinician name for an entry', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(clinicianName: 'Dr. Jane Doe')],
      )));
      await tester.pump();
      expect(find.text('Dr. Jane Doe'), findsOneWidget);
    });

    testWidgets('shows session summary text', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(summary: 'Patient is recovering well.')],
      )));
      await tester.pump();
      expect(find.text('Patient is recovering well.'), findsOneWidget);
    });

    testWidgets('shows Session Summary label', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry()],
      )));
      await tester.pump();
      expect(find.text('Session Summary'), findsOneWidget);
    });

    testWidgets('shows routine badge label', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(type: CheckInType.routine)],
      )));
      await tester.pump();
      expect(find.text('routine'), findsOneWidget);
    });

    testWidgets('shows urgent badge label', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(type: CheckInType.urgent)],
      )));
      await tester.pump();
      expect(find.text('urgent'), findsOneWidget);
    });

    testWidgets('shows follow-up badge label', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(type: CheckInType.followUp)],
      )));
      await tester.pump();
      expect(find.text('follow-up'), findsOneWidget);
    });

    testWidgets('shows mood label', (tester) async {
      await tester.pumpWidget(_wrap(VirtualCheckInHistoryCard(
        entries: [_entry(moodLabel: 'Fair')],
      )));
      await tester.pump();
      expect(find.text('Fair'), findsOneWidget);
    });
  });
}
