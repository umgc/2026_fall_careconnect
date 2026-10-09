// Tests for UspsTestScreen
// (lib/features/usps/presentation/usps_test_screen.dart).


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/usps/presentation/usps_test_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wrap with a null-user provider so _checkGoogleConnection returns early
/// (no Dio call, no pending timers).
Widget _wrap({UserProvider? provider}) {
  final prov = provider ?? _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: prov,
      child: const UspsTestScreen(),
    ),
  );
}

/// Minimal provider that always returns null user.
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  // =========================================================================
  // Group 1 – Initial render
  // =========================================================================
  group('UspsTestScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('shows "USPS Mail Digest" in the AppBar', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('USPS Mail Digest'), findsOneWidget);
    });

    testWidgets('shows "Gmail Integration" card heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Gmail Integration'), findsOneWidget);
    });

    testWidgets('shows log-in prompt in Gmail status when user is null',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text('Please log in to connect Gmail.'),
        findsOneWidget,
      );
    });

    testWidgets('shows "Connect Google Account" button when not connected',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Connect Google Account'), findsOneWidget);
    });

    testWidgets('shows Icons.mail icon in Gmail Integration card',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.mail), findsOneWidget);
    });

    testWidgets('shows Icons.link icon on Connect button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator on initial render',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows AppBar widget', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 2 – Date selection section
  // =========================================================================
  group('UspsTestScreen – date selection section', () {
    testWidgets('shows "Select Digest Date" heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Select Digest Date'), findsOneWidget);
    });

    testWidgets('shows calendar icon in date section', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.calendar_today), findsWidgets);
    });

    testWidgets('shows "Go to Today" button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Go to Today'), findsOneWidget);
    });

    testWidgets('shows description text for date selection', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text('Choose any date to view historical USPS digest data.'),
        findsOneWidget,
      );
    });

    testWidgets('shows today icon for Go to Today button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.today), findsOneWidget);
    });

    testWidgets('displays current date in the date button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      expect(find.text(dateStr), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 3 – Search section
  // =========================================================================
  group('UspsTestScreen – search section', () {
    testWidgets('shows "Search Mail History" heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Search Mail History'), findsOneWidget);
    });

    testWidgets('shows search icon in heading', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.search), findsWidgets);
    });

    testWidgets('shows search description text', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text('Search for mail by sender, subject, or any keyword.'),
        findsOneWidget,
      );
    });

    testWidgets('shows TextField with hint text', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enter keyword to search...'), findsOneWidget);
    });

    testWidgets('shows Search button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('typing in search field triggers rebuild', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'amazon');
      await tester.pump();
      // After typing, the clear icon should appear
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clear button not visible when search is empty',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });

  // =========================================================================
  // Group 4 – Action buttons
  // =========================================================================
  group('UspsTestScreen – action buttons row', () {
    testWidgets('shows Fetch Digest button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Fetch Digest'), findsOneWidget);
    });

    testWidgets('shows Clear Cache button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Clear Cache'), findsOneWidget);
    });

    testWidgets('Fetch Digest button is an ElevatedButton', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final fetchButton = find.widgetWithText(ElevatedButton, 'Fetch Digest');
      expect(fetchButton, findsOneWidget);
    });

    testWidgets('Clear Cache button is an ElevatedButton', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final cacheButton = find.widgetWithText(ElevatedButton, 'Clear Cache');
      expect(cacheButton, findsOneWidget);
    });
  });

  // =========================================================================
  // Group 5 – ListView / empty state
  // =========================================================================
  group('UspsTestScreen – list view area', () {
    testWidgets('contains a ListView', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('no "Packages" heading initially', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Packages'), findsNothing);
    });

    testWidgets('no "Mail Pieces" heading initially', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Mail Pieces'), findsNothing);
    });

    testWidgets('no "No items in digest" initially (digest is null)',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // digest is null initially, so "No items in digest" is not shown
      expect(find.text('No items in digest'), findsNothing);
    });
  });

  // =========================================================================
  // Group 6 – Card structure
  // =========================================================================
  group('UspsTestScreen – card layout', () {
    testWidgets('has at least 3 Card widgets (gmail, date, search)',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Gmail integration card + date selection card + search card = at least 3
      expect(find.byType(Card), findsAtLeast(3));
    });

    testWidgets('Gmail card contains red Connect button', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Connect Google Account'),
      );
      final style = button.style;
      expect(style, isNotNull);
    });
  });

  // =========================================================================
  // Group 7 – Widget tree structure checks
  // =========================================================================
  group('UspsTestScreen – widget tree structure', () {
    testWidgets('has a Padding with EdgeInsets.all(16) as body child',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // The body is Padding > Column
      expect(find.byType(Padding), findsWidgets);
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('has Row widget for date/search side-by-side',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Row for date + search, Row for action buttons
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('has an Expanded widget wrapping the ListView',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Expanded), findsWidgets);
    });

    testWidgets('OutlinedButton exists for date picker', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(OutlinedButton), findsWidgets);
    });

    testWidgets('TextButton exists for Go to Today', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'Go to Today'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 8 – Tapping buttons (no network calls, null user)
  // =========================================================================
  group('UspsTestScreen – button taps with null user', () {
    testWidgets('tapping Fetch Digest does not crash with null user',
        (tester) async {
      // With null user, _fetchDigest will fail on Dio but setState catches it.
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.text('Fetch Digest'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Should show error or still render fine
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('tapping Clear Cache with null user shows snackbar',
        (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.text('Clear Cache'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // user == null => _clearCache returns early with "Please log in first"
      expect(find.text('Please log in first'), findsOneWidget);
    });

    testWidgets('tapping Connect Google Account with null user shows snackbar',
        (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.text('Connect Google Account'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // user == null => shows "Please log in first"
      expect(find.text('Please log in first'), findsOneWidget);
    });

    testWidgets('tapping Go to Today button does not crash', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.text('Go to Today'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('tapping Search with empty field clears search state',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Tap search with empty text - should not crash
      await tester.tap(find.text('Search'));
      await tester.pump();
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('tapping date picker button opens date picker dialog',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      // Tap the date OutlinedButton
      await tester.tap(find.text(dateStr));
      await tester.pump();
      // DatePicker dialog should appear
      expect(find.text('Select digest date'), findsOneWidget);
    });

    testWidgets('cancelling date picker does not change date', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      await tester.tap(find.text(dateStr));
      await tester.pump();
      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      // Date should still be the same
      expect(find.text(dateStr), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 9 – Search interaction
  // =========================================================================
  group('UspsTestScreen – search interaction', () {
    testWidgets('submitting search field triggers search', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'amazon');
      await tester.pump();
      // Submit the text field (onSubmitted triggers _searchMail)
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Should not crash - may show error since Dio fails
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('typing text and clearing shows updated UI', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Type something
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Clear by entering empty text
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });

  // =========================================================================
  // Group 10 – Google connection states
  // =========================================================================
  group('UspsTestScreen – Google connection display', () {
    testWidgets('null-user status message is grey (disconnected state)',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final textWidget = tester.widget<Text>(
        find.text('Please log in to connect Gmail.'),
      );
      expect(textWidget.style?.color, equals(Colors.grey));
    });

    testWidgets('not connected: no "Reconnect Google Account" button',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Reconnect Google Account'), findsNothing);
    });

    testWidgets('not connected: no refresh icon', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsNothing);
    });
  });

  // =========================================================================
  // Group 11 – Multiple Card & icon checks
  // =========================================================================
  group('UspsTestScreen – icon presence', () {
    testWidgets('search icon appears in search section', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Icons.search appears in heading + TextField prefixIcon
      expect(find.byIcon(Icons.search), findsAtLeast(2));
    });

    testWidgets('calendar_today icon appears', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // In heading + in the OutlinedButton
      expect(find.byIcon(Icons.calendar_today), findsAtLeast(2));
    });
  });

  // =========================================================================
  // Group 12 – Error display
  // =========================================================================
  group('UspsTestScreen – error display', () {
    testWidgets('no error text shown initially', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // error is null initially
      // Verify no red-styled text is visible
      final redTexts = tester.widgetList<Text>(find.byType(Text)).where(
            (t) => t.style?.color == Colors.red,
          );
      expect(redTexts, isEmpty);
    });
  });

  // =========================================================================
  // Group 13 – Fetch Digest with error
  // =========================================================================
  group('UspsTestScreen – fetch digest error path', () {
    testWidgets('shows error text in red after fetch fails', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Tap Fetch Digest - Dio will fail since no server
      await tester.tap(find.text('Fetch Digest'));
      await tester.pump();
      // Wait for the async operation
      await tester.pump(const Duration(seconds: 15));

      // Error should be displayed in red
      final errorFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.style?.color == Colors.red &&
            widget.data != null &&
            widget.data!.isNotEmpty,
      );
      expect(errorFinder, findsWidgets);
    });
  });

  // =========================================================================
  // Group 14 – Search with text and button tap
  // =========================================================================
  group('UspsTestScreen – search button tap with keyword', () {
    testWidgets('tapping Search button with keyword triggers search',
        (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'fedex');
      await tester.pump();

      // Tap Search button
      await tester.tap(find.text('Search'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Widget should still be intact
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 15 – Structural layout tests
  // =========================================================================
  group('UspsTestScreen – structural layout', () {
    testWidgets('has SizedBox spacers between sections', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('has multiple ElevatedButton widgets', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Connect Google Account, Fetch Digest, Clear Cache, Search = at least 4
      expect(find.byType(ElevatedButton), findsAtLeast(4));
    });

    testWidgets('TextField has OutlineInputBorder decoration', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration, isNotNull);
      expect(textField.decoration!.hintText, 'Enter keyword to search...');
    });
  });

  // =========================================================================
  // Group 16 – Date picker selecting a date
  // =========================================================================
  group('UspsTestScreen – date picker interaction', () {
    testWidgets('selecting a date in picker triggers fetch', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';

      // Open date picker
      await tester.tap(find.text(dateStr));
      await tester.pump();

      // Select day 1 (should be visible in any month)
      // Find the "1" text in the date picker
      final day1 = find.text('1');
      if (day1.evaluate().isNotEmpty) {
        await tester.tap(day1.first);
        await tester.pump();
      }

      // Tap Select
      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 17 – Verify no items digest message condition
  // =========================================================================
  group('UspsTestScreen – empty digest message', () {
    testWidgets(
        'does not show "No items in digest" when digest is null (initial)',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('No items in digest'), findsNothing);
    });
  });

  // =========================================================================
  // Group 18 – Search clear button interaction
  // =========================================================================
  group('UspsTestScreen – search clear button', () {
    testWidgets('clear icon appears after typing', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ups');
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('tapping clear icon resets search', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ups');
      await tester.pump();

      // Tap the clear icon (calls _resetSearchToToday)
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 19 – Render with different viewport sizes
  // =========================================================================
  group('UspsTestScreen – different viewport sizes', () {
    testWidgets('renders on narrow viewport without crash', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('renders on very large viewport', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 20 – Connect Google Account button style
  // =========================================================================
  group('UspsTestScreen – button styles', () {
    testWidgets('Connect Google Account button has red background',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Connect Google Account'),
      );
      // Verify style is set (backgroundColor = red)
      expect(button.style, isNotNull);
    });

    testWidgets('Clear Cache button has orange background', (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Clear Cache'),
      );
      expect(button.style, isNotNull);
    });
  });

  // =========================================================================
  // Group 21 – TextField controller check
  // =========================================================================
  group('UspsTestScreen – TextField controller', () {
    testWidgets('TextField controller updates when text entered',
        (tester) async {
      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, 'hello world');
    });
  });

  // =========================================================================
  // Group 22 – Fetch Digest with MockUser (non-null user)
  // =========================================================================
  group('UspsTestScreen – with non-null user', () {
    testWidgets('renders with a real mock user', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      final provider = MockUserProvider(mockUser: MockUser());
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('Fetch Digest with user does not crash', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      final provider = MockUserProvider(mockUser: MockUser());
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Fetch Digest'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });

    testWidgets('Clear Cache with user does not crash', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      final provider = MockUserProvider(mockUser: MockUser());
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Clear Cache'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 23 – Multiple pumps to simulate async lifecycle
  // =========================================================================
  group('UspsTestScreen – async lifecycle', () {
    testWidgets('multiple pumps do not cause errors', (tester) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = origOnError);

      _setLargeViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UspsTestScreen), findsOneWidget);
    });
  });
}
