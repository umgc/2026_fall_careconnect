import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/shortcut_provider.dart';
import 'package:care_connect_app/widgets/menu/shortcut_search_delegate.dart';

/// Helper to create a ShortcutProvider with test data already loaded.
Future<ShortcutProvider> _createProvider() async {
  SharedPreferences.setMockInitialValues({});
  final sp = ShortcutProvider();
  await sp.init();
  return sp;
}

/// Wraps a test by providing a button that opens the search delegate.
/// This lets us test the delegate within its normal search context.
Widget _buildTestApp(ShortcutProvider provider,
    {String role = 'CAREGIVER', String userId = '42', bool allowPin = true}) {
  return ChangeNotifierProvider<ShortcutProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Test')),
          body: ElevatedButton(
            key: const Key('open_search'),
            onPressed: () {
              showSearch(
                context: context,
                delegate: ShortcutSearchDelegate(
                  roleUpper: role,
                  userId: userId,
                  allowPinToggle: allowPin,
                ),
              );
            },
            child: const Text('Search'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ShortcutSearchDelegate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('constructor sets searchFieldLabel', () {
      final delegate = ShortcutSearchDelegate(
        roleUpper: 'CAREGIVER',
        userId: '1',
      );
      expect(delegate.searchFieldLabel, 'Search features');
    });

    test('constructor defaults allowPinToggle to true', () {
      final delegate = ShortcutSearchDelegate(
        roleUpper: 'CAREGIVER',
        userId: '1',
      );
      expect(delegate.allowPinToggle, true);
    });

    test('constructor accepts allowPinToggle false', () {
      final delegate = ShortcutSearchDelegate(
        roleUpper: 'CAREGIVER',
        userId: '1',
        allowPinToggle: false,
      );
      expect(delegate.allowPinToggle, false);
    });

    testWidgets('opens search and shows suggestions (all features)',
        (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      // Tap the button to open search
      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Should show the search bar with the label
      expect(find.text('Search features'), findsOneWidget);

      // Should list built-in features visible for CAREGIVER
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Invoice Assistant'), findsOneWidget);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('buildActions shows clear button when query is not empty',
        (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Type a query
      await tester.enterText(find.byType(TextField), 'dash');
      await tester.pumpAndSettle();

      // Clear icon should appear
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clear button clears the query', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Type a query
      await tester.enterText(find.byType(TextField), 'dash');
      await tester.pumpAndSettle();

      // Tap clear
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // TextField should be empty again and all features visible
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('buildLeading shows back arrow', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('back arrow closes the search', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Tap back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back to original screen
      expect(find.text('Test'), findsOneWidget);
      expect(find.byKey(const Key('open_search')), findsOneWidget);
    });

    testWidgets('filters results based on query text', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Type a partial query
      await tester.enterText(find.byType(TextField), 'invoice');
      await tester.pumpAndSettle();

      // Should find Invoice Assistant
      expect(find.text('Invoice Assistant'), findsOneWidget);
      // Should not show unrelated features
      expect(find.text('EVV'), findsNothing);
      expect(find.text('Gamification'), findsNothing);
    });

    testWidgets('shows "No matches" when query has no results',
        (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'xyznonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('filters by role - PATIENT does not see EVV',
        (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider, role: 'PATIENT'));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // EVV is only visible for CAREGIVER/ADMIN
      expect(find.text('EVV'), findsNothing);
      // Dashboard is visible for all
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('shows pin icon for inactive items when allowPinToggle is true',
        (tester) async {
      final provider = await _createProvider();
      // Gamification is not active by default
      await tester.pumpWidget(_buildTestApp(provider, role: 'CAREGIVER'));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Should find pin icon for non-active shortcuts
      // Gamification defaultSelected=false, but after init all 8 defaults are active
      // so there should be at least the gam item showing a pin if not active
      // Since maxShortcuts is 8 and there are 8 defaults, gam is not active
      expect(find.byIcon(Icons.push_pin_outlined), findsWidgets);
    });

    testWidgets('no pin icon when allowPinToggle is false', (tester) async {
      final provider = await _createProvider();
      await tester
          .pumpWidget(_buildTestApp(provider, role: 'CAREGIVER', allowPin: false));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    });

    testWidgets('results rendered in ListView with Dividers',
        (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('each result shows an icon from ShortcutDef', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Dashboard uses Icons.dashboard
      expect(find.byIcon(Icons.dashboard), findsOneWidget);
      // Calendar uses Icons.calendar_today
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('search is case-insensitive', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'DASHBOARD');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('search matches route template too', (tester) async {
      final provider = await _createProvider();
      await tester.pumpWidget(_buildTestApp(provider));

      await tester.tap(find.byKey(const Key('open_search')));
      await tester.pumpAndSettle();

      // Type part of a route template
      await tester.enterText(find.byType(TextField), '/medication');
      await tester.pumpAndSettle();

      expect(find.text('Medication Management'), findsOneWidget);
    });
  });
}
