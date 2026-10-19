// Tests for MoodHistorySection widget
// (lib/features/health/caregiver-patient-list/widgets/mood_history_card.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/mood_history_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

MoodHistoryEntry _entry({
  String label = 'Good',
  int? score5 = 4,
  String? emoji = '🙂',
  String? note,
  DateTime? date,
}) =>
    MoodHistoryEntry(
      date: date ?? DateTime(2024, 6, 1),
      label: label,
      score5: score5,
      emoji: emoji,
      note: note,
    );

void main() {
  group('MoodHistorySection', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const MoodHistorySection(entries: [])));
      expect(find.byType(MoodHistorySection), findsOneWidget);
    });

    testWidgets('shows default Mood History title', (tester) async {
      await tester.pumpWidget(_wrap(const MoodHistorySection(entries: [])));
      expect(find.text('Mood History'), findsOneWidget);
    });

    testWidgets('shows custom title', (tester) async {
      await tester.pumpWidget(_wrap(const MoodHistorySection(
        entries: [],
        title: 'Weekly Mood',
      )));
      expect(find.text('Weekly Mood'), findsOneWidget);
    });

    testWidgets('shows empty state when no entries', (tester) async {
      await tester.pumpWidget(_wrap(const MoodHistorySection(entries: [])));
      expect(find.text('No mood history yet'), findsOneWidget);
    });

    testWidgets('shows favorite_border icon in header', (tester) async {
      await tester.pumpWidget(_wrap(const MoodHistorySection(entries: [])));
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('shows mood label for an entry', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [_entry(label: 'Excellent')],
      )));
      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('shows emoji for an entry', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [_entry(emoji: '😄')],
      )));
      expect(find.text('😄'), findsOneWidget);
    });

    testWidgets('shows Score text for an entry', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [_entry(score5: 4)],
      )));
      expect(find.text('Score: 4/5'), findsOneWidget);
    });

    testWidgets('shows note text when provided', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [_entry(note: 'Feeling better today')],
      )));
      expect(find.text('Feeling better today'), findsOneWidget);
    });

    testWidgets('shows multiple entries', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [
          _entry(label: 'Good', date: DateTime(2024, 6, 1)),
          _entry(label: 'Fair', score5: 3, emoji: '😐', date: DateTime(2024, 6, 2)),
        ],
      )));
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Fair'), findsOneWidget);
    });

    testWidgets('handles score10 entry', (tester) async {
      await tester.pumpWidget(_wrap(MoodHistorySection(
        entries: [
          MoodHistoryEntry(
            date: DateTime(2024, 6, 1),
            label: 'Good',
            score10: 8,
          ),
        ],
      )));
      // score10=8 maps to score5=5
      expect(find.text('Score: 5/5'), findsOneWidget);
    });
  });
}
