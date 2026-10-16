// Tests for MainFeedScreen
// (lib/features/social/presentation/pages/main_feed_screen.dart).
//
// With userId=0, initState skips fetchFeed() and the polling Timer, instead
// showing an empty feed immediately (isLoading=false, posts=[]).
// The showSnackBar call in that branch is wrapped in addPostFrameCallback,
// which fires AFTER build — no "during build" assertion error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/social/presentation/pages/main_feed_screen.dart';

Widget _wrap({int userId = 0}) =>
    MaterialApp(home: MainFeedScreen(userId: userId));

void main() {
  group('MainFeedScreen – userId=0 (no network, no timer)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(); // process addPostFrameCallback
      expect(find.byType(MainFeedScreen), findsOneWidget);
    });

    testWidgets('shows "My Feed" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('My Feed'), findsOneWidget);
    });

    testWidgets('shows "No posts yet. Pull to refresh." when empty',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('No posts yet. Pull to refresh.'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator when isLoading=false',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows no post ListTile items when posts are empty',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows SnackBar with invalid user message', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(); // process addPostFrameCallback
      expect(find.text('Invalid user ID. Please re-login.'), findsOneWidget);
    });

    testWidgets('shows RefreshIndicator or pull-to-refresh area', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // The empty state text indicates pull-to-refresh availability
      expect(find.textContaining('Pull to refresh'), findsOneWidget);
    });
  });
}
