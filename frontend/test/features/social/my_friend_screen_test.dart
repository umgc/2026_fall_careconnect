// Tests for MyFriendsScreen
// (lib/features/social/presentation/pages/my_friend_screen.dart).
//
// MyFriendsScreen reads UserProvider in addPostFrameCallback.
// When user is null: isLoading is set to false with no HTTP call.
// When user is non-null: fetchFriends() is called — safe to test initial
// loading state only (before pumpAndSettle advances the HTTP await).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/my_friend_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Widget _wrap({bool loggedIn = true}) {
  final provider = loggedIn
      ? MockUserProvider(mockUser: MockUser(id: 42, role: 'PATIENT'))
      : _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const MyFriendsScreen(),
    ),
  );
}

// Provider that always returns null user.
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('MyFriendsScreen – initial loading state (logged-in user)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      // Do NOT pumpAndSettle — that would await the HTTP call.
      expect(find.byType(MyFriendsScreen), findsOneWidget);
    });

    testWidgets('shows "My Friends" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // isLoading starts true, so progress indicator is shown immediately.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show a ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('MyFriendsScreen – null user', () {
    testWidgets('renders without crashing when user is null', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      await tester.pump(); // process setState(isLoading = false)
      expect(find.byType(MyFriendsScreen), findsOneWidget);
    });

    testWidgets('shows "My Friends" in AppBar when user is null', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      await tester.pump();
      expect(find.text('Contacts'), findsOneWidget);
    });

    testWidgets('shows empty-state text when user is null', (tester) async {
      // User is null → no friends fetched → empty-state message.
      await tester.pumpWidget(_wrap(loggedIn: false));
      await tester.pump(); // apply isLoading = false
      expect(find.text('No contacts found.'), findsOneWidget);
    });

    testWidgets('does NOT show ListView when user is null', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      await tester.pump();
      expect(find.byType(ListView), findsNothing);
    });
  });
}
