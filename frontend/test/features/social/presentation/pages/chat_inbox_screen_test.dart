// Tests for ChatInboxScreen
// (lib/features/social/presentation/pages/chat_inbox_screen.dart).
//
// ChatInboxScreen reads UserProvider in didChangeDependencies.
// When user is non-null: _userId is set, fetchInbox() starts (HTTP call),
// and isLoading=true on the initial render — safe to test AppBar + spinner
// without calling pumpAndSettle.
//
// NOTE: The null-user path calls ScaffoldMessenger.showSnackBar inside
// didChangeDependencies (during build), which Flutter prohibits — those
// paths cannot be exercised in widget tests without modifying the source.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_inbox_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Widget _wrap() => MaterialApp(
      home: ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 7, role: 'PATIENT')),
        child: const ChatInboxScreen(),
      ),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ChatInboxScreen – logged-in user (initial loading state)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      // Do NOT pumpAndSettle — the HTTP fetchInbox() is in flight.
      expect(find.byType(ChatInboxScreen), findsOneWidget);
    });

    testWidgets('shows "Messages" in the AppBar', (tester) async {
      // _userId is set → full Scaffold with AppBar is rendered.
      await tester.pumpWidget(_wrap());
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows My Friends icon button in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.group), findsOneWidget);
    });

    testWidgets('does NOT show a ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar or title area', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });
  });
}
