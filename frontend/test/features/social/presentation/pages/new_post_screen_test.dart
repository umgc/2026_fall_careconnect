// Tests for NewPostScreen
// (lib/features/social/presentation/pages/new_post_screen.dart).
//
// NewPostScreen reads UserProvider in build (not initState).
// Null user: shows "User not logged in" fallback immediately.
// Non-null user: shows the post creation form.
// No API calls in initState.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/new_post_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap({bool loggedIn = true}) {
  final provider = loggedIn
      ? MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'))
      : _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const NewPostScreen(),
    ),
  );
}

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

void main() {
  group('NewPostScreen – logged-in user', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(NewPostScreen), findsOneWidget);
    });

    testWidgets('shows "Create New Post" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Create New Post'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Post" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Post'), findsOneWidget);
    });

    testWidgets('does NOT show "User not logged in" for logged-in user',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('User not logged in'), findsNothing);
    });
  });

  group('NewPostScreen – null user', () {
    testWidgets('shows "User not logged in" when user is null', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      expect(find.text('User not logged in'), findsOneWidget);
    });

    testWidgets('shows "Create New Post" AppBar even when null user',
        (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      expect(find.text('Create New Post'), findsOneWidget);
    });

    testWidgets('shows back arrow for null user', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('does NOT show Post button when null user', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      expect(find.text('Post'), findsNothing);
    });

    testWidgets('does NOT show TextFormField when null user', (tester) async {
      await tester.pumpWidget(_wrap(loggedIn: false));
      expect(find.byType(TextFormField), findsNothing);
    });
  });

  group('NewPostScreen – form elements', () {
    testWidgets('shows TextFormField for post content', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows content input hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('What\u2019s on your mind?'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton for Post', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows back arrow button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('Post button is enabled initially', (tester) async {
      await tester.pumpWidget(_wrap());
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('can enter text in content field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.byType(TextFormField), 'Hello world!');
      expect(find.text('Hello world!'), findsOneWidget);
    });

    testWidgets('shows SnackBar when posting with empty content', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Post'));
      await tester.pump();
      expect(find.text('Post content cannot be empty'), findsOneWidget);
    });
  });
}
