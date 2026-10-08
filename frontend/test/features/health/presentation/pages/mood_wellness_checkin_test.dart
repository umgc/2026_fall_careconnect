// Tests for MoodWellnessCheckIn
// (lib/features/health/presentation/pages/mood_wellness_checkin.dart).
//
// No initState override and no API calls at startup.
// Submission is triggered by user action only.
// Uses larger viewport to avoid Column overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/presentation/pages/mood_wellness_checkin.dart';

Widget _wrap() => const MaterialApp(home: MoodWellnessCheckIn());

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  group('MoodWellnessCheckIn – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(MoodWellnessCheckIn), findsOneWidget);
    });

    testWidgets('shows "Mood & Wellness Check-In" in AppBar', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('Mood & Wellness Check-In'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator initially',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows "How are you feeling today?" heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('How are you feeling today?'), findsOneWidget);
    });

    testWidgets('shows "Pain Level:" heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('Pain Level:'), findsOneWidget);
    });

    testWidgets('shows two Slider widgets (mood and pain)', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('shows mood emoji text for default value 5', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('Mood:'), findsOneWidget);
    });

    testWidgets('shows pain emoji text for default value 5', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('Pain:'), findsOneWidget);
    });

    testWidgets('shows notes TextField', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows hint text in notes field', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('Write about your day or feelings here... (optional)'),
          findsOneWidget);
    });

    testWidgets('shows "Would you like to share anything else?" label',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('Would you like to share anything else?'), findsOneWidget);
    });

    testWidgets('shows Submit button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton for submit', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  group('MoodWellnessCheckIn – interaction', () {
    testWidgets('can enter text in notes field', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.byType(TextField), 'Feeling great today');
      expect(find.text('Feeling great today'), findsOneWidget);
    });

    testWidgets('Submit button is enabled initially', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
