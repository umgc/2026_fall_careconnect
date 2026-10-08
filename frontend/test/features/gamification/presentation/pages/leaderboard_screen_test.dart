// Tests for LeaderboardScreen
// (lib/features/gamification/presentation/pages/leaderboard_screen.dart).
//
// LeaderboardScreen calls fetchLeaderboard() in initState but renders a
// CircularProgressIndicator while isLoading=true (the initial state).
// The HTTP request fails silently in tests (catch prints error, no setState),
// so the widget remains in the loading state — safe to test that initial render.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/gamification/presentation/pages/leaderboard_screen.dart';

Widget _wrap() =>
    const MaterialApp(home: LeaderboardScreen());

void main() {
  group('LeaderboardScreen – initial (loading) state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      // Do NOT call pumpAndSettle — that would wait for the HTTP call forever.
      expect(find.byType(LeaderboardScreen), findsOneWidget);
    });

    testWidgets('shows "Leaderboard" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Leaderboard'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // On first render isLoading=true, so a progress indicator is shown.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does NOT show leaderboard list while loading', (tester) async {
      // No ListView should be visible while isLoading=true.
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center widget while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show "No leaderboard data" while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('No leaderboard data available.'), findsNothing);
    });

    testWidgets('does NOT show any Card while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('does NOT show any ListTile while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('AppBar has blue shade 900 background', (tester) async {
      await tester.pumpWidget(_wrap());
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.blue.shade900);
    });

    testWidgets('does NOT show CircleAvatar while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('does NOT show person icon while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.person), findsNothing);
    });
  });
}
