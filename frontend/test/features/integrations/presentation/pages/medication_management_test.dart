// Tests for MedicationManagementScreen
// (lib/features/integrations/presentation/pages/medication_management.dart).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/medication_management.dart';

/// Wraps [child] with a UserProvider (needed by the embedded CommonDrawer).
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'cg@example.com',
    role: 'CAREGIVER',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

/// A comprehensive medication fixture that exercises every conditional branch
/// in _buildMedicationList (dosage, timeToTake, takeWith, doNotTakeWith,
/// startDate, endDate) and _formatDateRange / _formatDate.
final _medicationFull = {
  'id': 'med-001',
  'brandName': 'Aspirin',
  'genericName': 'Acetylsalicylic acid',
  'strength': '100mg',
  'dosage': '1 tablet',
  'frequency': 'Daily',
  'timeToTake': 'Morning',
  'takeWith': 'Water',
  'doNotTakeWith': 'Alcohol',
  'startDate': '2024-01-01',
  'endDate': '2024-12-31',
};

/// A minimal medication (no optional fields) to cover the null-fallback branches.
final _medicationMinimal = {
  'id': 'med-002',
  'brandName': 'Ibuprofen',
  'genericName': null,
  'strength': null,
};

/// Medication with only startDate (no endDate) to cover "From X" branch.
final _medicationStartOnly = {
  'id': 'med-003',
  'brandName': 'Tylenol',
  'genericName': 'Acetaminophen',
  'strength': '500mg',
  'dosage': '',
  'frequency': '',
  'timeToTake': '',
  'takeWith': '',
  'doNotTakeWith': '',
  'startDate': '2024-06-01',
  'endDate': null,
};

/// Medication with only endDate (no startDate) to cover "Until X" branch.
final _medicationEndOnly = {
  'id': 'med-004',
  'brandName': 'Metformin',
  'genericName': 'Metformin HCl',
  'strength': '850mg',
  'dosage': '',
  'frequency': '',
  'timeToTake': '',
  'takeWith': '',
  'doNotTakeWith': '',
  'startDate': null,
  'endDate': '2025-03-01',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // ── empty-medications state ───────────────────────────────────────────────

  group('MedicationManagementScreen - empty state', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Scaffold after medications load', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "No Medications Added" when no medications are saved', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No Medications Added'), findsOneWidget);
    });

    testWidgets('shows "Medication Management" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Medication Management'), findsOneWidget);
    });

    testWidgets('shows "Scan Medication Barcode" button', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Scan Medication Barcode'), findsOneWidget);
    });

    testWidgets('shows "Enter NDC Code" button', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter NDC Code'), findsOneWidget);
    });

    testWidgets('shows "Add Medication Manually" button', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Add Medication Manually'), findsOneWidget);
    });

    testWidgets('shows descriptive text in empty state', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Scan medication barcodes'),
        findsOneWidget,
      );
    });

    testWidgets('shows medication icon in empty state', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.medication), findsOneWidget);
    });

    testWidgets('shows add icon button in AppBar when empty', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('does not show share icon in AppBar when no medications',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // share icon should not appear in AppBar additionalActions when empty
      expect(find.byTooltip('Share medication list'), findsNothing);
    });
  });

  // ── pre-seeded medications state ─────────────────────────────────────────

  group('MedicationManagementScreen - with pre-seeded medications', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('renders "Current Medications" heading', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Current Medications'), findsOneWidget);
    });

    testWidgets('shows the medication brand name', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Aspirin'), findsOneWidget);
    });

    testWidgets('shows the medication generic name', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Acetylsalicylic acid'), findsOneWidget);
    });

    testWidgets('shows strength label', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Strength: 100mg'), findsOneWidget);
    });

    testWidgets('shows dosage and frequency conditional row', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dosage:'), findsOneWidget);
      expect(find.textContaining('Daily'), findsOneWidget);
    });

    testWidgets('shows time-to-take conditional row', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Time to take:'), findsOneWidget);
      expect(find.textContaining('Morning'), findsOneWidget);
    });

    testWidgets('shows take-with conditional row', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Take with:'), findsOneWidget);
    });

    testWidgets('shows do-not-take-with conditional row', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Do not take with:'), findsOneWidget);
    });

    testWidgets('shows duration date range conditional row', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Duration:'), findsOneWidget);
    });

    testWidgets('shows PopupMenuButton for each medication', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('PopupMenu shows Edit and Remove items', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('tapping Remove deletes the medication from the list', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Aspirin'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Medication'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(find.text('No Medications Added'), findsOneWidget);
    });

    testWidgets('shows medication count in header', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('medications being managed'),
        findsOneWidget,
      );
    });

    testWidgets('shows share icon in medication list header', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.share), findsWidgets);
    });

    testWidgets('shows add_circle icon in medication list header',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle), findsOneWidget);
    });

    testWidgets('date range formats as "start to end" when both dates present',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // _formatDateRange with both dates: "1/1/2024 to 31/12/2024"
      expect(find.textContaining('1/1/2024'), findsOneWidget);
      expect(find.textContaining('31/12/2024'), findsOneWidget);
    });

    testWidgets('remove confirmation dialog shows cancel button',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel remove confirmation keeps medication', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Medication should still be shown
      expect(find.text('Aspirin'), findsOneWidget);
    });
  });

  // ── minimal medication (null-fallback branches) ───────────────────────────

  group('MedicationManagementScreen - minimal medication (null fallbacks)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationMinimal]),
      });
    });

    testWidgets('renders brand name with null generic fallback', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Ibuprofen'), findsOneWidget);
      expect(find.text('Unknown Generic'), findsOneWidget);
    });

    testWidgets('renders "Not specified" when strength is null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not specified'), findsOneWidget);
    });

    testWidgets('does not show dosage row when dosage is absent',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dosage:'), findsNothing);
    });

    testWidgets('does not show time-to-take when absent', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Time to take:'), findsNothing);
    });

    testWidgets('does not show take-with when absent', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Take with:'), findsNothing);
    });

    testWidgets('does not show do-not-take-with when absent', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Do not take with:'), findsNothing);
    });

    testWidgets('does not show duration when no dates', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Duration:'), findsNothing);
    });
  });

  // ── _formatDateRange branches ──────────────────────────────────────────────

  group('MedicationManagementScreen - _formatDateRange branches', () {
    testWidgets('shows "From X" when only startDate is set', (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationStartOnly]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // _formatDateRange with only startDate: "From 1/6/2024"
      expect(find.textContaining('Duration:'), findsOneWidget);
      expect(find.textContaining('From'), findsOneWidget);
    });

    testWidgets('shows "Until X" when only endDate is set', (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationEndOnly]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Duration:'), findsOneWidget);
      expect(find.textContaining('Until'), findsOneWidget);
    });
  });

  // ── multiple medications ─────────────────────────────────────────────────

  group('MedicationManagementScreen - multiple medications', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull, _medicationMinimal]),
      });
    });

    testWidgets('shows correct count for multiple medications', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 medications being managed'), findsOneWidget);
    });

    testWidgets('renders PopupMenuButton for each medication', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
    });

    testWidgets('shows both medication brand names', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Aspirin'), findsOneWidget);
      expect(find.text('Ibuprofen'), findsOneWidget);
    });
  });

  // ── Add Medication Manually dialog ──────────────────────────────────────

  group('MedicationManagementScreen - Add Medication Manually dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('tapping "Add Medication Manually" opens add dialog',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Add Medication Manually'), findsNWidgets(2));
      expect(find.text('Brand Name *'), findsOneWidget);
    });

    testWidgets(
        'add manually dialog shows all expected fields', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Brand Name *'), findsOneWidget);
      expect(find.text('Generic Name'), findsOneWidget);
      expect(find.text('Strength (e.g., 10mg)'), findsOneWidget);
      expect(find.text('Dosage Form (e.g., Tablet)'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text('NDC Code (optional)'), findsOneWidget);
    });

    testWidgets('add manually dialog has Cancel and Add Medication buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Add Medication'), findsOneWidget);
    });

    testWidgets(
        'add manually dialog shows validation when brand name is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Tap Add Medication without entering brand name
      await tester.tap(find.text('Add Medication'));
      await tester.pump();

      expect(find.text('Brand name is required'), findsOneWidget);
    });

    testWidgets('add manually dialog cancel closes dialog', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog title should be gone (only one instance from the button)
      expect(find.text('Brand Name *'), findsNothing);
    });

    testWidgets(
        'successfully adds a medication manually with only brand name',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Enter brand name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'TestMed',
      );
      await tester.pumpAndSettle();

      // Tap Add Medication
      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Should now show the medication in the list
      expect(find.text('TestMed'), findsOneWidget);
      expect(find.text('Current Medications'), findsOneWidget);
    });

    testWidgets(
        'successfully adds medication with all fields filled',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'FullMed',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Generic Name'),
        'FullGeneric',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Strength (e.g., 10mg)'),
        '50mg',
      );

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      expect(find.text('FullMed'), findsOneWidget);
      expect(find.text('FullGeneric'), findsOneWidget);
    });

    testWidgets(
        'shows select start/end date placeholders in add dialog',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Select Start Date (optional)'), findsOneWidget);
      expect(find.text('Select End Date (optional)'), findsOneWidget);
    });

    testWidgets(
        'shows treatment fields in add dialog (dosage, frequency, time, etc.)',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Dosage (e.g., 1 tablet)'), findsOneWidget);
      expect(find.text('Frequency (e.g., Twice daily)'), findsOneWidget);
      expect(find.text('Time to Take (e.g., 8:00 PM)'), findsOneWidget);
      expect(find.text('Take With (e.g., milk, food)'), findsOneWidget);
      expect(
        find.text('Do Not Take With (e.g., alcohol, other meds)'),
        findsOneWidget,
      );
    });
  });

  // ── Enter NDC Code dialog ────────────────────────────────────────────────

  group('MedicationManagementScreen - Enter NDC Code dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('tapping "Enter NDC Code" opens NDC dialog', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Enter NDC Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter NDC Code'), findsNWidgets(2));
      expect(find.text('Product NDC'), findsOneWidget);
    });

    testWidgets('NDC dialog has Cancel and Lookup buttons', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Enter NDC Code'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Lookup'), findsOneWidget);
    });

    testWidgets('NDC dialog shows format hint', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Enter NDC Code'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('XXXXX-XXX'),
        findsOneWidget,
      );
    });

    testWidgets('NDC dialog shows validation when empty code submitted',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Enter NDC Code'));
      await tester.pumpAndSettle();

      // Tap Lookup without entering code
      await tester.tap(find.text('Lookup'));
      await tester.pump();

      expect(find.text('Please enter an NDC code'), findsOneWidget);
    });

    testWidgets('NDC dialog cancel closes dialog', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Enter NDC Code'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Product NDC'), findsNothing);
    });
  });

  // ── Navigate to Add Medication (bottom sheet) ──────────────────────────

  group('MedicationManagementScreen - Add Medication bottom sheet', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('tapping add_circle icon opens bottom sheet', (tester) async {
      // Use a larger surface to avoid overflow
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Add Medication'), findsOneWidget);
      expect(find.text('Scan Barcode'), findsOneWidget);
      expect(find.text('Enter NDC Code'), findsOneWidget);
      expect(find.text('Add Manually'), findsOneWidget);
    });

    testWidgets('bottom sheet shows subtitles for each option', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(
        find.text('Use camera to scan medication barcode'),
        findsOneWidget,
      );
      expect(find.text('Type NDC code manually'), findsOneWidget);
      expect(find.text('Enter medication details manually'), findsOneWidget);
    });

    testWidgets('tapping AppBar add icon opens bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // The AppBar has an add icon
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Add Medication'), findsOneWidget);
    });
  });

  // ── Edit Medication dialog ──────────────────────────────────────────────

  group('MedicationManagementScreen - Edit Medication dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('tapping Edit opens edit dialog with pre-filled fields',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Medication'), findsOneWidget);
      expect(find.text('Brand Name *'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('edit dialog has Cancel and Save Changes buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('edit dialog cancel preserves original medication',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Aspirin'), findsOneWidget);
    });

    testWidgets('edit dialog shows validation when brand name is cleared',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Clear brand name field
      final brandField = find.widgetWithText(TextField, 'Brand Name *');
      await tester.enterText(brandField, '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(find.text('Brand name is required'), findsOneWidget);
    });

    testWidgets('edit dialog saves changes successfully', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Change brand name
      final brandField = find.widgetWithText(TextField, 'Brand Name *');
      await tester.enterText(brandField, 'Aspirin Extra');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Aspirin Extra'), findsOneWidget);
      expect(find.text('Medication updated successfully!'), findsOneWidget);
    });

    testWidgets('edit dialog shows date pickers for start and end date',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Since the medication has dates, it should show formatted dates
      expect(find.textContaining('Start Date:'), findsOneWidget);
      expect(find.textContaining('End Date:'), findsOneWidget);
    });

    testWidgets('edit dialog has clear buttons for set dates', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Clear icons should be present for both dates
      expect(find.byIcon(Icons.clear), findsNWidgets(2));
    });
  });

  // ── Edit with duplicate detection ─────────────────────────────────────────

  group('MedicationManagementScreen - duplicate detection in edit', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull, _medicationMinimal]),
      });
    });

    testWidgets(
        'edit dialog shows duplicate warning when renaming to existing name',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Tap the first medication's popup menu
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Change brand name to match the second medication
      final brandField = find.widgetWithText(TextField, 'Brand Name *');
      await tester.enterText(brandField, 'Ibuprofen');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(
        find.text('A medication with this name already exists'),
        findsOneWidget,
      );
    });
  });

  // ── Duplicate detection in manual add ──────────────────────────────────

  group(
      'MedicationManagementScreen - duplicate detection in manual add', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets(
        'manual add shows duplicate warning when adding existing brand name',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Use the AppBar add icon to open bottom sheet, then "Add Manually"
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Enter the same brand name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'Aspirin',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Should show duplicate warning dialog
      expect(find.text('Duplicate Medication Warning'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Add Anyway'), findsOneWidget);
    });

    testWidgets('cancel duplicate warning keeps only original medication',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'Aspirin',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Cancel duplicate warning
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Should still have only 1 medication
      expect(
        find.textContaining('1 medications being managed'),
        findsOneWidget,
      );
    });

    testWidgets('"Add Anyway" in duplicate warning adds the medication',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'Aspirin',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Tap "Add Anyway" in duplicate warning
      await tester.tap(find.text('Add Anyway'));
      await tester.pumpAndSettle();

      // Should now have 2 medications
      expect(
        find.textContaining('2 medications being managed'),
        findsOneWidget,
      );
    });
  });

  // ── Medication with no brandName (Unknown Medication fallback) ────────

  group('MedicationManagementScreen - brandName null fallback', () {
    testWidgets('shows "Unknown Medication" when brandName is null',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([
          {
            'id': 'med-x',
            'brandName': null,
            'genericName': 'SomeGeneric',
            'strength': '10mg',
          }
        ]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Unknown Medication'), findsOneWidget);
    });
  });

  // ── Medication with frequency null (As needed fallback) ──────────────

  group('MedicationManagementScreen - frequency fallback', () {
    testWidgets('shows "As needed" when frequency is null but dosage present',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([
          {
            'id': 'med-y',
            'brandName': 'TestDrug',
            'genericName': 'TestGeneric',
            'strength': '5mg',
            'dosage': '2 tablets',
            'frequency': null,
          }
        ]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('As needed'), findsOneWidget);
    });
  });

  // ── Invalid JSON in SharedPreferences (error branch) ────────────────

  group('MedicationManagementScreen - load error handling', () {
    testWidgets('handles invalid JSON gracefully', (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': 'not valid json {{{',
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Should show empty state (error caught, isLoading set to false)
      expect(find.text('No Medications Added'), findsOneWidget);
    });
  });

  // ── Bottom sheet actions ───────────────────────────────────────────────

  group('MedicationManagementScreen - bottom sheet navigation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('bottom sheet "Enter NDC Code" opens NDC dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter NDC Code'));
      await tester.pumpAndSettle();

      // NDC dialog should be visible
      expect(find.text('Product NDC'), findsOneWidget);
    });

    testWidgets('bottom sheet "Add Manually" opens manual add dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Brand Name *'), findsOneWidget);
    });
  });

  // ── Medication with empty string optional fields ──────────────────────

  group('MedicationManagementScreen - empty string optional fields', () {
    testWidgets('does not show conditional rows for empty strings',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([
          {
            'id': 'med-empty',
            'brandName': 'EmptyFields',
            'genericName': 'Generic',
            'strength': '10mg',
            'dosage': '',
            'frequency': '',
            'timeToTake': '',
            'takeWith': '',
            'doNotTakeWith': '',
          }
        ]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.text('EmptyFields'), findsOneWidget);
      expect(find.textContaining('Dosage:'), findsNothing);
      expect(find.textContaining('Time to take:'), findsNothing);
      expect(find.textContaining('Take with:'), findsNothing);
      expect(find.textContaining('Do not take with:'), findsNothing);
    });
  });

  // ── Edit medication with minimal data (no dates) ─────────────────────

  group('MedicationManagementScreen - Edit minimal medication', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationMinimal]),
      });
    });

    testWidgets('edit dialog for minimal medication shows placeholder dates',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Select Start Date (optional)'), findsOneWidget);
      expect(find.text('Select End Date (optional)'), findsOneWidget);
      // No clear icons since dates are null
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });

  // ── Removed medication persists to SharedPreferences ──────────────────

  group('MedicationManagementScreen - persistence', () {
    testWidgets('removed medication is persisted to SharedPreferences',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Remove the medication
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      // Verify empty state
      expect(find.text('No Medications Added'), findsOneWidget);

      // Verify SharedPreferences was updated
      final prefs = await SharedPreferences.getInstance();
      final savedMeds = prefs.getString('medications');
      expect(savedMeds, isNotNull);
      final decoded = jsonDecode(savedMeds!);
      expect(decoded, isEmpty);
    });

    testWidgets('manually added medication is persisted', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'PersistTest',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Verify SharedPreferences was updated
      final prefs = await SharedPreferences.getInstance();
      final savedMeds = prefs.getString('medications');
      expect(savedMeds, isNotNull);
      final decoded = jsonDecode(savedMeds!) as List;
      expect(decoded.length, 1);
      expect(decoded[0]['brandName'], 'PersistTest');
    });
  });

  // ── Edit and save medication with updated values ──────────────────────

  group('MedicationManagementScreen - Edit and save updated values', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('editing generic name updates the displayed value',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final genericField = find.widgetWithText(TextField, 'Generic Name');
      await tester.enterText(genericField, 'New Generic Name');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('New Generic Name'), findsOneWidget);
    });
  });

  // ── Medication list rendering details ──────────────────────────────────

  group('MedicationManagementScreen - list rendering details', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('medication card has medication icon', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.medication), findsWidgets);
    });

    testWidgets('medication list uses Card widgets', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('medication list uses ListTile', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsOneWidget);
    });
  });

  // ── NDC lookup via Enter NDC Code dialog (mocked HTTP) ────────────────

  group('MedicationManagementScreen - NDC lookup with mocked HTTP', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('successful NDC lookup shows medication details dialog',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'Tylenol',
            'generic_name': 'Acetaminophen',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [
              {'strength': '500', 'unit': 'mg'}
            ],
            'labeler_name': 'Johnson & Johnson',
            'proprietary_name': 'Tylenol',
            'nonproprietary_name': 'Acetaminophen',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          // Open NDC dialog
          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          // Enter NDC code
          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '50580-937',
          );
          await tester.pumpAndSettle();

          // Tap Lookup
          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Should show the medication details dialog
          expect(find.text('Tylenol'), findsOneWidget);
          expect(find.text('Treatment Information:'), findsOneWidget);
          expect(find.text('Generic Name:'), findsOneWidget);
          expect(find.text('Dosage Form:'), findsOneWidget);
          expect(find.text('Strength:'), findsOneWidget);
          expect(find.text('Manufacturer:'), findsOneWidget);
          expect(find.text('NDC Code:'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });

    testWidgets(
        'successful NDC lookup - adding medication from details dialog',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'Advil',
            'generic_name': 'Ibuprofen',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [
              {'strength': '200', 'unit': 'mg'}
            ],
            'labeler_name': 'Pfizer',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '12345-678',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Tap "Add Medication" in the details dialog
          await tester.tap(find.text('Add Medication'));
          await tester.pumpAndSettle();

          // Should now show the medication in the list
          expect(find.text('Advil'), findsOneWidget);
          expect(find.text('Current Medications'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });

    testWidgets('NDC lookup with 404 shows not found snackbar',
        (tester) async {
      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '99999-999',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          expect(
            find.textContaining('NDC code not found'),
            findsOneWidget,
          );
        },
        () => MockClient(
            (request) async => http.Response('{"error":"NOT_FOUND"}', 404)),
      );
    });

    testWidgets('NDC lookup with server error shows error snackbar',
        (tester) async {
      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '11111-222',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          expect(
            find.textContaining('Error looking up medication'),
            findsOneWidget,
          );
        },
        () => MockClient(
            (request) async => http.Response('Server Error', 500)),
      );
    });

    testWidgets(
        'NDC lookup shows loading state while fetching', (tester) async {
      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '50580-937',
          );
          await tester.pumpAndSettle();

          // Tap Lookup - use pump() not pumpAndSettle() to see loading state
          await tester.tap(find.text('Lookup'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Should show loading text
          expect(find.text('Looking up...'), findsOneWidget);

          // Let it complete
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          // Small delay to ensure loading state is visible
          await Future.delayed(const Duration(milliseconds: 100));
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'brand_name': 'TestDrug',
                  'generic_name': 'TestGeneric',
                  'dosage_form_name': 'Tablet',
                  'active_ingredients': [],
                  'labeler_name': 'TestLab',
                }
              ],
            }),
            200,
          );
        }),
      );
    });

    testWidgets(
        'medication details dialog has Close button', (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'Motrin',
            'generic_name': 'Ibuprofen',
            'dosage_form_name': 'Caplet',
            'active_ingredients': [
              {'strength': '400', 'unit': 'mg'}
            ],
            'labeler_name': 'McNeil',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '50580-111',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Close button should be present
          expect(find.text('Close'), findsOneWidget);

          // Tap Close
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();

          // Should be back to empty state
          expect(find.text('No Medications Added'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });

    testWidgets(
        'medication details dialog shows date picker placeholders',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'Benadryl',
            'generic_name': 'Diphenhydramine',
            'dosage_form_name': 'Capsule',
            'active_ingredients': [
              {'strength': '25', 'unit': 'mg'}
            ],
            'labeler_name': 'J&J',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '50580-222',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Date picker placeholders
          expect(
            find.text('Select Start Date (optional)'),
            findsOneWidget,
          );
          expect(
            find.text('Select End Date (optional)'),
            findsOneWidget,
          );

          // Treatment info fields
          expect(find.text('Dosage (e.g., 1 tablet)'), findsOneWidget);
          expect(
            find.text('Frequency (e.g., Twice daily)'),
            findsOneWidget,
          );
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });

    testWidgets(
        'NDC lookup with empty results returns null', (tester) async {
      final fdaResponse = jsonEncode({
        'results': [],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '00000-000',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // null result should show snackbar (code reaches null return)
          // The code returns null when results is empty, which means
          // medicationData == null path is taken
          expect(
            find.textContaining('NDC code not found'),
            findsOneWidget,
          );
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });
  });

  // ── Add medication manually with all optional fields ──────────────────

  group('MedicationManagementScreen - manual add with all fields', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('adds medication with all optional fields filled',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Fill all fields
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'TestBrand',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Generic Name'),
        'TestGeneric',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Strength (e.g., 10mg)'),
        '100mg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dosage Form (e.g., Tablet)'),
        'Tablet',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Manufacturer'),
        'TestMfg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'NDC Code (optional)'),
        '12345-678',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dosage (e.g., 1 tablet)'),
        '2 tablets',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Frequency (e.g., Twice daily)'),
        'Once daily',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Time to Take (e.g., 8:00 PM)'),
        '9:00 AM',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Take With (e.g., milk, food)'),
        'Food',
      );
      await tester.enterText(
        find.widgetWithText(
            TextField, 'Do Not Take With (e.g., alcohol, other meds)'),
        'Alcohol',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Verify the medication was added with all fields
      expect(find.text('TestBrand'), findsOneWidget);
      expect(find.text('TestGeneric'), findsOneWidget);
      expect(find.textContaining('Strength: 100mg'), findsOneWidget);
      expect(find.textContaining('Dosage: 2 tablets'), findsOneWidget);
      expect(find.textContaining('Time to take: 9:00 AM'), findsOneWidget);
      expect(find.textContaining('Take with: Food'), findsOneWidget);
      expect(find.textContaining('Do not take with: Alcohol'), findsOneWidget);
    });
  });

  // ── Edit dialog - clearing dates ──────────────────────────────────────

  group('MedicationManagementScreen - edit dialog date clearing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('clearing start date in edit dialog removes it',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // There should be 2 clear icons (start and end date)
      expect(find.byIcon(Icons.clear), findsNWidgets(2));

      // Scroll to make the clear buttons visible, then tap
      final clearFirst = find.byIcon(Icons.clear).first;
      await tester.ensureVisible(clearFirst);
      await tester.pumpAndSettle();
      await tester.tap(clearFirst);
      await tester.pumpAndSettle();

      // Start date should now show placeholder
      expect(find.text('Select Start Date (optional)'), findsOneWidget);

      // Only 1 clear icon remaining (end date)
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clearing end date in edit dialog removes it',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Scroll to make the last clear button visible
      final clearLast = find.byIcon(Icons.clear).last;
      await tester.ensureVisible(clearLast);
      await tester.pumpAndSettle();
      await tester.tap(clearLast);
      await tester.pumpAndSettle();

      // End date should now show placeholder
      expect(find.text('Select End Date (optional)'), findsOneWidget);
    });

    testWidgets('saving after clearing dates persists the change',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Clear first date
      final clearFirst = find.byIcon(Icons.clear).first;
      await tester.ensureVisible(clearFirst);
      await tester.pumpAndSettle();
      await tester.tap(clearFirst);
      await tester.pumpAndSettle();

      // Clear remaining date
      final clearRemaining = find.byIcon(Icons.clear).first;
      await tester.ensureVisible(clearRemaining);
      await tester.pumpAndSettle();
      await tester.tap(clearRemaining);
      await tester.pumpAndSettle();

      // Scroll to Save Changes and tap
      final saveBtn = find.text('Save Changes');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Duration row should no longer be displayed
      expect(find.textContaining('Duration:'), findsNothing);
    });
  });

  // ── Edit dialog with all fields ───────────────────────────────────────

  group('MedicationManagementScreen - edit dialog all fields', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets('edit dialog shows all text fields for medication',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Brand Name *'), findsOneWidget);
      expect(find.text('Generic Name'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Dosage Form'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text('Dosage'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
    });

    testWidgets('edit dialog shows time/interaction fields', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(
        find.text('Time to Take (e.g., 8:00 PM)'),
        findsOneWidget,
      );
      expect(
        find.text('Take With (e.g., milk, food)'),
        findsOneWidget,
      );
      expect(
        find.text('Do Not Take With (e.g., alcohol, other meds)'),
        findsOneWidget,
      );
    });

    testWidgets(
        'edit dialog shows access_time and local_dining and warning icons',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.access_time), findsOneWidget);
      expect(find.byIcon(Icons.local_dining), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });
  });

  // ── _showDuplicateWarningManual "Add Anyway" path ─────────────────────

  group('MedicationManagementScreen - duplicate manual add "Add Anyway"', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });
    });

    testWidgets(
        '"Add Anyway" in duplicate manual warning adds and shows snackbar',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Open add manually dialog (using empty state button won't work, use the NDC code approach)
      // Actually, the main screen has medications so we don't see the empty state buttons.
      // We need to use the AppBar add icon -> bottom sheet -> Add Manually
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Enter duplicate brand name with generic name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'Aspirin',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Generic Name'),
        'New Aspirin Generic',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Duplicate warning should appear
      expect(find.text('Duplicate Medication Warning'), findsOneWidget);

      // Tap "Add Anyway"
      await tester.tap(find.text('Add Anyway'));
      await tester.pumpAndSettle();

      // Should have 2 medications now
      expect(
        find.textContaining('2 medications being managed'),
        findsOneWidget,
      );
      // Success snackbar
      expect(find.textContaining('added successfully'), findsOneWidget);
    });
  });

  // ── NDC lookup duplicate detection ────────────────────────────────────

  group('MedicationManagementScreen - NDC lookup duplicate detection', () {
    testWidgets(
        'NDC lookup finding duplicate shows warning and Add Anyway works',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([
          {
            'id': 'med-dup',
            'brandName': 'Tylenol',
            'genericName': 'Acetaminophen',
            'strength': '500mg',
          }
        ]),
      });

      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'Tylenol',
            'generic_name': 'Acetaminophen',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [
              {'strength': '500', 'unit': 'mg'}
            ],
            'labeler_name': 'J&J',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          // Open NDC dialog via add_circle -> bottom sheet -> Enter NDC Code
          tester.view.physicalSize = const Size(800, 1200);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());
          addTearDown(() => tester.view.resetDevicePixelRatio());

          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.add));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '50580-937',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Should show duplicate warning
          expect(
              find.text('Duplicate Medication Warning'), findsOneWidget);
          expect(find.text('Add Anyway'), findsOneWidget);

          // Tap "Add Anyway"
          await tester.tap(find.text('Add Anyway'));
          await tester.pumpAndSettle();

          // Should show medication details dialog after accepting duplicate
          expect(find.text('Tylenol'), findsWidgets);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });
  });

  // ── _parseNDCResult with missing active ingredients ───────────────────

  group('MedicationManagementScreen - NDC result with missing ingredients',
      () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('handles medication with no active_ingredients',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'NoIngredients',
            'generic_name': 'TestGeneric',
            'dosage_form_name': 'Capsule',
            'active_ingredients': [],
            'labeler_name': 'TestLab',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '55555-555',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Should show the medication name
          expect(find.text('NoIngredients'), findsOneWidget);
          // Should show "Unknown Strength" since no active ingredients
          expect(find.text('Unknown Strength'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });

    testWidgets('handles medication with fallback names', (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'proprietary_name': 'ProprietaryName',
            'nonproprietary_name': 'NonProprietary',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [],
            'labeler_name': 'TestLab',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '66666-666',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Should use proprietary_name as fallback for brand_name
          expect(find.text('ProprietaryName'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });
  });

  // ── Duplicate by generic name ─────────────────────────────────────────

  group('MedicationManagementScreen - duplicate detection by generic name',
      () {
    testWidgets(
        'detects duplicate by generic name match (different brand name)',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      // Open add manually via bottom sheet
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Enter different brand name but same generic name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'DifferentBrand',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Generic Name'),
        'Acetylsalicylic acid',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Should show duplicate warning (matched by generic name)
      expect(find.text('Duplicate Medication Warning'), findsOneWidget);
    });
  });

  // ── _showDuplicateWarningManual Add Anyway with all fields ────────────

  group('MedicationManagementScreen - duplicate manual add preserves fields',
      () {
    testWidgets(
        '"Add Anyway" from duplicate manual warning preserves all entered fields',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationFull]),
      });

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Manually'));
      await tester.pumpAndSettle();

      // Fill in fields
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'Aspirin',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Generic Name'),
        'DupGeneric',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Strength (e.g., 10mg)'),
        '200mg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dosage Form (e.g., Tablet)'),
        'Capsule',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Manufacturer'),
        'DupMfg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'NDC Code (optional)'),
        '99999-999',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dosage (e.g., 1 tablet)'),
        '3 tablets',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Frequency (e.g., Twice daily)'),
        'Twice daily',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Time to Take (e.g., 8:00 PM)'),
        '10:00 PM',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Take With (e.g., milk, food)'),
        'Milk',
      );
      await tester.enterText(
        find.widgetWithText(
            TextField, 'Do Not Take With (e.g., alcohol, other meds)'),
        'Grapefruit',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Duplicate warning
      expect(find.text('Duplicate Medication Warning'), findsOneWidget);

      await tester.tap(find.text('Add Anyway'));
      await tester.pumpAndSettle();

      // Should have 2 medications
      expect(
        find.textContaining('2 medications being managed'),
        findsOneWidget,
      );
    });
  });

  // ── Medication details dialog - add with treatment info ───────────────

  group(
      'MedicationManagementScreen - medication details dialog with treatment',
      () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'adds medication from details dialog with treatment info filled',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'DetailTest',
            'generic_name': 'DetailGeneric',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [
              {'strength': '100', 'unit': 'mg'}
            ],
            'labeler_name': 'DetailLab',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '77777-777',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Fill treatment info
          await tester.enterText(
            find.widgetWithText(TextField, 'Dosage (e.g., 1 tablet)'),
            '1 tablet',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Frequency (e.g., Twice daily)'),
            'Daily',
          );
          await tester.enterText(
            find.widgetWithText(
                TextField, 'Time to Take (e.g., 8:00 PM)'),
            '8:00 AM',
          );
          await tester.enterText(
            find.widgetWithText(
                TextField, 'Take With (e.g., milk, food)'),
            'Food',
          );
          await tester.enterText(
            find.widgetWithText(
                TextField,
                'Do Not Take With (e.g., alcohol, other meds)'),
            'Alcohol',
          );
          await tester.pumpAndSettle();

          // Tap Add Medication
          await tester.tap(find.text('Add Medication'));
          await tester.pumpAndSettle();

          // Medication should appear in the list with all info
          expect(find.text('DetailTest'), findsOneWidget);
          expect(find.textContaining('Dosage: 1 tablet'), findsOneWidget);
          expect(
              find.textContaining('Time to take: 8:00 AM'), findsOneWidget);
          expect(find.textContaining('Take with: Food'), findsOneWidget);
          expect(find.textContaining('Do not take with: Alcohol'),
              findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });
  });

  // ── Scan Medication Barcode button in empty state ─────────────────────

  group('MedicationManagementScreen - button icons', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('scan barcode button has qr_code_scanner icon',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    });

    testWidgets('enter NDC code button has keyboard icon', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard), findsOneWidget);
    });

    testWidgets('add manually button has edit icon', (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  // ── Date picker interactions in add dialog ─────────────────────────────

  group('MedicationManagementScreen - date picker in add dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('tapping start date opens date picker and selects a date',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Scroll to the start date InkWell
      final startDateInkWell = find.text('Select Start Date (optional)');
      await tester.ensureVisible(startDateInkWell);
      await tester.pumpAndSettle();

      // Tap the start date row
      await tester.tap(startDateInkWell);
      await tester.pumpAndSettle();

      // DatePicker should be visible
      expect(find.text('OK'), findsOneWidget);

      // Tap OK to select today's date
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Start date should now show formatted date instead of placeholder
      expect(find.text('Select Start Date (optional)'), findsNothing);
      expect(find.textContaining('Start Date:'), findsOneWidget);
    });

    testWidgets('tapping end date opens date picker and selects a date',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Scroll to the end date InkWell
      final endDateInkWell = find.text('Select End Date (optional)');
      await tester.ensureVisible(endDateInkWell);
      await tester.pumpAndSettle();

      // Tap the end date row
      await tester.tap(endDateInkWell);
      await tester.pumpAndSettle();

      // DatePicker should be visible
      expect(find.text('OK'), findsOneWidget);

      // Tap OK
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // End date should now show formatted date
      expect(find.text('Select End Date (optional)'), findsNothing);
      expect(find.textContaining('End Date:'), findsOneWidget);
    });

    testWidgets('adding medication with dates selected includes dates',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Fill brand name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'DateTestMed',
      );
      await tester.pumpAndSettle();

      // Select start date
      final startDateInkWell = find.text('Select Start Date (optional)');
      await tester.ensureVisible(startDateInkWell);
      await tester.pumpAndSettle();
      await tester.tap(startDateInkWell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Select end date
      final endDateInkWell = find.text('Select End Date (optional)');
      await tester.ensureVisible(endDateInkWell);
      await tester.pumpAndSettle();
      await tester.tap(endDateInkWell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Add the medication
      final addBtn = find.text('Add Medication');
      await tester.ensureVisible(addBtn);
      await tester.pumpAndSettle();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Medication should be added with duration showing
      expect(find.text('DateTestMed'), findsOneWidget);
      expect(find.textContaining('Duration:'), findsOneWidget);
    });

    testWidgets('cancelling date picker does not set a date',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      final startDateInkWell = find.text('Select Start Date (optional)');
      await tester.ensureVisible(startDateInkWell);
      await tester.pumpAndSettle();

      await tester.tap(startDateInkWell);
      await tester.pumpAndSettle();

      // Tap CANCEL instead of OK
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Placeholder should still be there
      expect(find.text('Select Start Date (optional)'), findsOneWidget);
    });
  });

  // ── Date picker interactions in edit dialog ───────────────────────────

  group('MedicationManagementScreen - date picker in edit dialog', () {
    testWidgets('tapping start date in edit opens date picker',
        (tester) async {
      // Use a medication without dates so we can test opening the picker
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationMinimal]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Scroll to start date
      final startDate = find.text('Select Start Date (optional)');
      await tester.ensureVisible(startDate);
      await tester.pumpAndSettle();

      await tester.tap(startDate);
      await tester.pumpAndSettle();

      // DatePicker should appear
      expect(find.text('OK'), findsOneWidget);

      // Select the date
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Should now show the date
      expect(find.textContaining('Start Date:'), findsOneWidget);
    });

    testWidgets('tapping end date in edit opens date picker',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'medications': jsonEncode([_medicationMinimal]),
      });

      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Scroll to end date
      final endDate = find.text('Select End Date (optional)');
      await tester.ensureVisible(endDate);
      await tester.pumpAndSettle();

      await tester.tap(endDate);
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('End Date:'), findsOneWidget);
    });
  });

  // ── Date picker interactions in medication details dialog ─────────────

  group('MedicationManagementScreen - date picker in details dialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('selecting dates in details dialog then adding medication',
        (tester) async {
      final fdaResponse = jsonEncode({
        'results': [
          {
            'brand_name': 'DatePickerTest',
            'generic_name': 'DateGeneric',
            'dosage_form_name': 'Tablet',
            'active_ingredients': [
              {'strength': '50', 'unit': 'mg'}
            ],
            'labeler_name': 'DateLab',
          }
        ],
      });

      await http.runWithClient(
        () async {
          await tester
              .pumpWidget(_wrap(const MedicationManagementScreen()));
          await tester.pumpAndSettle();

          await tester.tap(find.textContaining('Enter NDC Code'));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.widgetWithText(TextField, 'Product NDC'),
            '88888-888',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lookup'));
          await tester.pumpAndSettle();

          // Should see the details dialog
          expect(find.text('DatePickerTest'), findsOneWidget);

          // Tap start date
          final startDate = find.text('Select Start Date (optional)');
          await tester.ensureVisible(startDate);
          await tester.pumpAndSettle();
          await tester.tap(startDate);
          await tester.pumpAndSettle();

          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();

          expect(find.textContaining('Start Date:'), findsOneWidget);

          // Tap end date
          final endDate = find.text('Select End Date (optional)');
          await tester.ensureVisible(endDate);
          await tester.pumpAndSettle();
          await tester.tap(endDate);
          await tester.pumpAndSettle();

          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();

          expect(find.textContaining('End Date:'), findsOneWidget);

          // Add the medication
          final addBtn = find.text('Add Medication');
          await tester.ensureVisible(addBtn);
          await tester.pumpAndSettle();
          await tester.tap(addBtn);
          await tester.pumpAndSettle();

          // Should be added with duration
          expect(find.text('DatePickerTest'), findsOneWidget);
          expect(find.textContaining('Duration:'), findsOneWidget);
        },
        () => MockClient(
            (request) async => http.Response(fdaResponse, 200)),
      );
    });
  });

  // ── Additional add manually coverage - default values ─────────────────

  group('MedicationManagementScreen - add manually default values', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'adds medication with empty optional fields sets "Not specified" defaults',
        (tester) async {
      await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication Manually'));
      await tester.pumpAndSettle();

      // Only fill brand name
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand Name *'),
        'DefaultsTest',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Verify medication was added
      expect(find.text('DefaultsTest'), findsOneWidget);
      // genericName defaults to "Not specified"
      expect(find.text('Not specified'), findsOneWidget);
      // Verify it's persisted
      final prefs = await SharedPreferences.getInstance();
      final savedMeds = prefs.getString('medications');
      final decoded = jsonDecode(savedMeds!) as List;
      expect(decoded[0]['genericName'], 'Not specified');
      expect(decoded[0]['strength'], 'Not specified');
      expect(decoded[0]['dosageForm'], 'Not specified');
      expect(decoded[0]['manufacturer'], 'Not specified');
      expect(decoded[0]['ndc'], 'Manual Entry');
      expect(decoded[0]['isManualEntry'], true);
    });
  });
}
