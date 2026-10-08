// Tests for SearchUserScreen
// (lib/features/social/presentation/pages/search_user_screen.dart).
//
// SearchUserScreen reads UserProvider from context — no API calls on initial
// render (isLoading=false at startup; search only triggers on button tap).
//
// Tests wrap with MockUserProvider from test/mock_user_provider.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/search_user_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap({bool loggedIn = true}) {
  final provider = MockUserProvider(
    mockUser: loggedIn ? MockUser(id: 1, role: 'PATIENT') : null,
  );
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const SearchUserScreen(),
    ),
  );
}

void main() {
  group('SearchUserScreen – logged-in user', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SearchUserScreen), findsOneWidget);
    });

    testWidgets('shows "Search Users" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Search Users'), findsWidgets);
    });

    testWidgets('shows search TextField', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows search icon button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows no ListTile results on initial render', (tester) async {
      // No search has been performed yet — no result tiles are visible.
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('does NOT show CircularProgressIndicator on initial render',
        (tester) async {
      // isLoading starts false, so no progress spinner is shown.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows "Search by name or email" label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Search by name or email'), findsOneWidget);
    });

    testWidgets('can enter text in search field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.byType(TextField), 'John');
      expect(find.text('John'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('SearchUserScreen – null user', () {
    testWidgets('shows "User not logged in" when user is null', (tester) async {
      // When user=null the screen shows a fallback message.
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: nullProvider,
          child: const SearchUserScreen(),
        ),
      ));
      expect(find.text('User not logged in'), findsOneWidget);
    });

    testWidgets('shows AppBar with "Search Users" for null user', (tester) async {
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: nullProvider,
          child: const SearchUserScreen(),
        ),
      ));
      expect(find.text('Search Users'), findsOneWidget);
    });

    testWidgets('does NOT show search TextField for null user', (tester) async {
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: nullProvider,
          child: const SearchUserScreen(),
        ),
      ));
      expect(find.byType(TextField), findsNothing);
    });
  });
}

// Minimal UserProvider that always returns null user.
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}
