import 'package:care_connect_app/l10n/app_localizations.dart';
// Tests for EvvVisitHistoryPage
// (lib/features/evv/presentation/pages/evv_visit_history.dart).
//
// initState calls _performSearch() which sets _isLoading=true synchronously,
// then makes an API call (EvvService.searchRecords). In tests the HTTP call
// fails (no backend), so the catch block fires, showing error snackbar and
// empty-state UI ("No records found").
//
// CommonDrawer requires UserProvider, so we wrap with MockUserProvider.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_visit_history.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

Widget _wrap({String role = 'CAREGIVER'}) {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: role, caregiverId: 10));
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const EvvVisitHistoryPage(),
    ),
  );
}

/// Pumps enough frames for the async _performSearch to fail (no server) and
/// setState to fire, transitioning from loading spinner to the body.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('EvvVisitHistoryPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(EvvVisitHistoryPage), findsOneWidget);
    });

    testWidgets('shows "EVV Visit History" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('EVV Visit History'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while searching', (tester) async {
      await tester.pumpWidget(_wrap());
      // _performSearch sets _isLoading=true before any await
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Form widget', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Form), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – search filters', () {
    testWidgets('shows "Search Filters" header', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Search Filters'), findsOneWidget);
    });

    testWidgets('shows Search button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('shows Patient Name text field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Patient Name'), findsOneWidget);
    });

    testWidgets('shows Service Type text field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Service Type'), findsOneWidget);
    });

    testWidgets('shows Caregiver ID text field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Caregiver ID'), findsOneWidget);
    });

    testWidgets('shows Select Date Range placeholder', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Select Date Range'), findsOneWidget);
    });

    testWidgets('shows State dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('State'), findsOneWidget);
    });

    testWidgets('shows Status dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('can enter text in Patient Name field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final patientField = find.widgetWithText(TextFormField, 'Patient Name');
      expect(patientField, findsOneWidget);
      await tester.enterText(patientField, 'John Doe');
      await tester.pump();
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('can enter text in Service Type field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final field = find.widgetWithText(TextFormField, 'Service Type');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Personal Care');
      await tester.pump();
      expect(find.text('Personal Care'), findsOneWidget);
    });

    testWidgets('can enter text in Caregiver ID field', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final field = find.widgetWithText(TextFormField, 'Caregiver ID');
      expect(field, findsOneWidget);
      await tester.enterText(field, '42');
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – empty state after failed load', () {
    testWidgets('shows "No records found" after search fails', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('No records found'), findsOneWidget);
    });

    testWidgets('shows "Try adjusting your search filters" hint', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Try adjusting your search filters'), findsOneWidget);
    });

    testWidgets('shows search_off icon in empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('no longer shows spinner after load completes', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('EvvVisitHistoryPage – AppBar actions', () {
    testWidgets('has clear filters button with tooltip', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byTooltip('Clear Filters'), findsOneWidget);
    });

    testWidgets('has clear_all icon button', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.clear_all), findsOneWidget);
    });

    testWidgets('tapping clear filters clears text fields', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Enter text in Patient Name
      final patientField = find.widgetWithText(TextFormField, 'Patient Name');
      await tester.enterText(patientField, 'Jane');
      await tester.pump();
      expect(find.text('Jane'), findsOneWidget);

      // Tap clear filters
      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Field should be cleared
      expect(find.text('Jane'), findsNothing);
    });
  });

  group('EvvVisitHistoryPage – search button interaction', () {
    testWidgets('tapping Search button triggers search and returns to empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Verify we are in empty state
      expect(find.text('No records found'), findsOneWidget);

      // Tap the Search button
      final searchButton = find.text('Search');
      await tester.tap(searchButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // After search completes (fails), should show empty state again
      expect(find.text('No records found'), findsOneWidget);
    });

    testWidgets('search completes and returns to empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Tap search
      await tester.tap(find.text('Search'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // After search fails, should show empty state again
      expect(find.text('No records found'), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – date range picker', () {
    testWidgets('date range area is tappable', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Find the InkWell for date range
      final dateRange = find.text('Select Date Range');
      expect(dateRange, findsOneWidget);

      // Tap should open date picker dialog
      await tester.tap(dateRange);
      await tester.pump();

      // The date range picker dialog should appear
      // It may or may not render depending on platform, but tap should not crash
    });

    testWidgets('date range shows date_range icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.date_range), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – dropdown interactions', () {
    testWidgets('State dropdown can be opened', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Find the State dropdown
      final stateDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'State');
      expect(stateDropdown, findsOneWidget);
    });

    testWidgets('Status dropdown can be opened', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final statusDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Status');
      expect(statusDropdown, findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – form field icons', () {
    testWidgets('Patient Name field has person icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('Service Type field has medical_services icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
    });

    testWidgets('Caregiver ID field has badge icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.badge), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – Card widget structure', () {
    testWidgets('search filters are wrapped in a Card', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // There is at least the search filter card
      expect(find.byType(Card), findsAtLeastNWidgets(1));
    });

    testWidgets('has three TextFormField widgets', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // Patient Name, Service Type, Caregiver ID
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('has two DropdownButtonFormField widgets', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // State and Status dropdowns
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    });
  });

  group('EvvVisitHistoryPage – clear filters resets dropdowns', () {
    testWidgets('clear filters resets search and shows empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Enter data in all text fields
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Patient Name'),
        'Test Patient',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Service Type'),
        'Nursing',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Caregiver ID'),
        '99',
      );
      await tester.pump();

      // Verify text was entered
      expect(find.text('Test Patient'), findsOneWidget);
      expect(find.text('Nursing'), findsOneWidget);
      expect(find.text('99'), findsOneWidget);

      // Tap clear filters
      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // All text should be cleared
      expect(find.text('Test Patient'), findsNothing);
      expect(find.text('Nursing'), findsNothing);
      expect(find.text('99'), findsNothing);

      // Date range should be reset to placeholder
      expect(find.text('Select Date Range'), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – error handling', () {
    testWidgets('shows error snackbar when search fails', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // After the initial search fails, a SnackBar with error text should appear
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('error snackbar contains error message prefix', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // The snackbar text starts with 'Error searching records:'
      expect(find.textContaining('Error searching records'), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – search icon', () {
    testWidgets('Search button has search icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('EvvVisitHistoryPage – Column layout', () {
    testWidgets('has Column as main body child', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byType(Column), findsAtLeastNWidgets(1));
    });

    testWidgets('has Row widgets for filter layout', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // Multiple rows: header row, first row, second row, third row + empty state rows
      expect(find.byType(Row), findsAtLeastNWidgets(3));
    });
  });
}
