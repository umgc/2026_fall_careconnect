// Tests for MealTrackingScreen
// (lib/features/health/presentation/pages/meal_tracking_screen.dart).
//
// initState calls _loadMealQuestions() which is synchronous (no HTTP).
// No Provider needed. Pure form widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/presentation/pages/meal_tracking_screen.dart';

Widget _wrap() => const MaterialApp(home: MealTrackingScreen());

void main() {
  group('MealTrackingScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(MealTrackingScreen), findsOneWidget);
    });

    testWidgets('shows "Meal & Nutrition Tracking" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Meal & Nutrition Tracking'), findsOneWidget);
    });

    testWidgets('shows instruction text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.text('Please answer the following questions:'),
        findsOneWidget,
      );
    });

    testWidgets('shows multiple TextFields for meal responses', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('MealTrackingScreen – meal questions', () {
    testWidgets('shows breakfast question', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('What did you eat for breakfast?'), findsOneWidget);
    });

    testWidgets('shows lunch question', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('What did you eat for lunch?'), findsOneWidget);
    });

    testWidgets('shows dinner question', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('What did you eat for dinner?'), findsOneWidget);
    });

    testWidgets('shows water question', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Did you drink enough water today?'), findsOneWidget);
    });

    testWidgets('shows snacks question', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Did you eat any snacks today?'), findsOneWidget);
    });

    testWidgets('shows exactly 5 TextFields', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsNWidgets(5));
    });

    testWidgets('TextFields have hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Your answer...'), findsNWidgets(5));
    });
  });

  group('MealTrackingScreen – submit button', () {
    testWidgets('shows Submit Meal Log button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Submit Meal Log'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('tapping submit shows SnackBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Submit Meal Log'));
      await tester.pump();
      await tester.tap(find.text('Submit Meal Log'));
      await tester.pump();
      expect(find.text('Meal log submitted successfully.'), findsOneWidget);
    });

    testWidgets('tapping submit clears text fields', (tester) async {
      await tester.pumpWidget(_wrap());
      // Enter text in the first TextField
      await tester.enterText(find.byType(TextField).first, 'Eggs and toast');
      expect(find.text('Eggs and toast'), findsOneWidget);
      // Submit
      await tester.ensureVisible(find.text('Submit Meal Log'));
      await tester.pump();
      await tester.tap(find.text('Submit Meal Log'));
      await tester.pump();
      // Text should be cleared
      expect(find.text('Eggs and toast'), findsNothing);
    });

    testWidgets('submit with filled fields then clears all', (tester) async {
      await tester.pumpWidget(_wrap());
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Cereal');
      await tester.enterText(textFields.at(1), 'Sandwich');
      await tester.enterText(textFields.at(2), 'Pasta');
      expect(find.text('Cereal'), findsOneWidget);
      expect(find.text('Sandwich'), findsOneWidget);
      expect(find.text('Pasta'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit Meal Log'));
      await tester.pump();
      await tester.tap(find.text('Submit Meal Log'));
      await tester.pump();
      expect(find.text('Cereal'), findsNothing);
      expect(find.text('Sandwich'), findsNothing);
      expect(find.text('Pasta'), findsNothing);
      expect(find.text('Meal log submitted successfully.'), findsOneWidget);
    });
  });

  group('MealTrackingScreen – layout', () {
    testWidgets('uses SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('uses Column layout', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });
  });
}
