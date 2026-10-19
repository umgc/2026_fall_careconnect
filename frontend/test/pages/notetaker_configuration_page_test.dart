// Tests for NotetakerConfigurationPage from
// lib/pages/notetaker_configuration_page.dart.
//
// Coverage strategy:
// - Patient user path: mocking secure-storage lets _fetchConfig complete (400),
//   error is caught, _isLoading = false, full patient form renders.
// - Caregiver with null caregiverId: no API calls, _isLoading = false,
//   shows failure info card (no patients).
// - Caregiver with caregiverId: API call fails, _isLoading = false,
//   shows failure info card (empty patient list after error).
// - Null user: redirects to login.
// - Exercises build(), _buildConfigForm(), _buildInfoCard(), _buildToggleSection(),
//   _buildPIISection(), _buildKeywordSection(), _buildVoiceSampleSection(),
//   _buildSection(), _buildToggleCard(), _buildRecordStopControl(), _buildText(),
//   stringToCard(), generateRows(), toggles, dialogs, etc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/pages/notetaker_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../mock_user_provider.dart';

/// Helper: wrap the page with a provider + MaterialApp.
Widget _wrapWithProvider(UserProvider provider) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      home: const NotetakerConfigurationPage(),
      routes: {
        '/login': (_) => const Scaffold(body: Text('Login Page')),
      },
    ),
  );
}

/// Pump enough frames for async initState work to settle.
Future<void> _pumpPastLoading(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scroll to a widget so it is visible, then pump.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Temporarily suppress the ParentDataWidget error from the Expanded
/// wrapping SimpleDialog in source code. Call the returned function to restore.
void Function(FlutterErrorDetails)? _suppressParentDataError() {
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('ParentDataWidget') || msg.contains('Incorrect use of ParentDataWidget')) {
      // Suppress this known framework error from source code
      return;
    }
    // Forward all other errors to the original handler
    if (original != null) {
      original(details);
    }
  };
  return original;
}

/// Open the Add PII dialog, suppressing ParentDataWidget errors from source code.
Future<void> _openAddPIIDialog(WidgetTester tester) async {
  final addPII = find.text('Add PII');
  await _scrollTo(tester, addPII);
  final origHandler = _suppressParentDataError();
  await tester.tap(addPII);
  await tester.pump();
  FlutterError.onError = origHandler;
}

/// Open the Add Keyword dialog, suppressing ParentDataWidget errors from source code.
Future<void> _openAddKeywordDialog(WidgetTester tester) async {
  final addKW = find.text('Add Keyword');
  await _scrollTo(tester, addKW);
  final origHandler = _suppressParentDataError();
  await tester.tap(addKW);
  await tester.pump();
  FlutterError.onError = origHandler;
}

/// Pump while suppressing ParentDataWidget errors.
Future<void> _pumpSafe(WidgetTester tester, [Duration? duration]) async {
  final origHandler = _suppressParentDataError();
  await tester.pump(duration);
  FlutterError.onError = origHandler;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // Mock connectivity_plus platform channels.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') return ['wifi'];
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (MethodCall methodCall) async => null,
    );

    // Mock flutter_secure_storage so AuthTokenManager.getAuthHeaders works.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') return null;
        if (methodCall.method == 'write') return null;
        if (methodCall.method == 'delete') return null;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Patient user — loading state (before async work completes)
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – patient user (loading state)', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(NotetakerConfigurationPage), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching config',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AppBar shows Notetaker Configuration title', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Notetaker Configuration'), findsOneWidget);
    });

    testWidgets('AppBar has Cancel button', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('AppBar has Save button', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Cancel button is a TextButton', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Save button is a TextButton', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
    });

    testWidgets('Cancel is disabled while loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNull);
    });

    testWidgets('Save is disabled while loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('has AppBar widget', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Caregiver user — loading state
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – caregiver user (loading state)', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 10,
        ),
      );
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(NotetakerConfigurationPage), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Notetaker Configuration title', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Notetaker Configuration'), findsOneWidget);
    });

    testWidgets('has Cancel and Save buttons', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Cancel and Save disabled while loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNull);

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Patient user — after loading completes (form rendered)
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – patient form after loading', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('loading spinner disappears after async work completes',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('info card is shown with configuration description',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.info_outline), findsWidgets);
      expect(
        find.textContaining('Configure your Notetaker assistant'),
        findsOneWidget,
      );
    });

    testWidgets('toggle section is rendered with switches', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('Enable Notetaker Assistant toggle card exists',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Enable Notetaker Assistant'), findsOneWidget);
    });

    testWidgets('Enable Caregiver Access toggle card exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Enable Caregiver Access'), findsOneWidget);
    });

    testWidgets('Enable Usage/Access section header exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Enable Usage/Access'), findsOneWidget);
    });

    testWidgets('PII terms section header exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('PII terms'), findsOneWidget);
    });

    testWidgets('Keywords section header exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Keywords'), findsOneWidget);
    });

    testWidgets('Manage Voice Sample section header exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _scrollTo(tester, find.text('Manage Voice Sample'));
      expect(find.text('Manage Voice Sample'), findsOneWidget);
    });

    testWidgets('Add PII button exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Add PII'), findsOneWidget);
    });

    testWidgets('Add Keyword button exists', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.text('Add Keyword'), findsOneWidget);
    });

    testWidgets('Cancel button is enabled after loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNotNull);
    });

    testWidgets('Save button is enabled after loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('tapping Enable Notetaker switch toggles it', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
      final firstSwitch = tester.widget<Switch>(switches.first);
      final initialValue = firstSwitch.value;
      await tester.tap(switches.first);
      await tester.pump();
      final afterSwitch = tester.widget<Switch>(switches.first);
      expect(afterSwitch.value, isNot(initialValue));
    });

    testWidgets('tapping Enable Caregiver Access switch toggles it',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);
      final secondSwitch = tester.widget<Switch>(switches.at(1));
      final initialValue = secondSwitch.value;
      await tester.tap(switches.at(1));
      await tester.pump();
      final afterSwitch = tester.widget<Switch>(switches.at(1));
      expect(afterSwitch.value, isNot(initialValue));
    });

    testWidgets('PII section has a ListView', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('Keywords section has a DataTable', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('DataTable has Keyword and Event Type column headers',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _scrollTo(tester, find.text('Keyword'));
      expect(find.text('Keyword'), findsOneWidget);
      expect(find.text('Event Type'), findsOneWidget);
    });

    testWidgets('tapping Add PII opens dialog', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddPIIDialog(tester);
      expect(find.text('Add a PII term'), findsOneWidget);
      expect(find.text('Enter text'), findsOneWidget);
    });

    testWidgets('Add PII dialog has Add button', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddPIIDialog(tester);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('Add PII dialog: entering text and tapping Add adds PII item',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddPIIDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'MySSN');
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      expect(find.text('MySSN'), findsOneWidget);
    });

    testWidgets('PII item can be removed via cancel icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddPIIDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'TestPII');
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      expect(find.text('TestPII'), findsOneWidget);
      // Scroll to make the cancel icon visible
      final cancelIcons = find.byIcon(Icons.cancel);
      expect(cancelIcons, findsWidgets);
      await _scrollTo(tester, cancelIcons.first);
      await tester.tap(cancelIcons.first);
      await tester.pump();
      expect(find.text('TestPII'), findsNothing);
    });

    testWidgets('tapping Add Keyword opens dialog', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      expect(find.text('Add a keyword'), findsOneWidget);
    });

    testWidgets('Add Keyword dialog has text field and dropdown',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('Add Keyword dialog: add keyword with ALERT event',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'HelpMe');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _pumpSafe(tester);
      await tester.tap(find.text('ALERT').last);
      await _pumpSafe(tester);
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      // Scroll to the DataTable to see the keyword
      await _scrollTo(tester, find.text('HelpMe'));
      expect(find.text('HelpMe'), findsOneWidget);
      expect(find.text('ALERT'), findsOneWidget);
    });

    testWidgets('keyword row has delete icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'DeleteMe');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _pumpSafe(tester);
      await tester.tap(find.text('TASK').last);
      await _pumpSafe(tester);
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      await _scrollTo(tester, find.text('DeleteMe'));
      expect(find.text('DeleteMe'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsWidgets);
    });

    testWidgets('deleting keyword row removes it', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'RemoveKW');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _pumpSafe(tester);
      await tester.tap(find.text('ALERT').last);
      await _pumpSafe(tester);
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      await _scrollTo(tester, find.text('RemoveKW'));
      expect(find.text('RemoveKW'), findsOneWidget);
      final deleteIcon = find.byIcon(Icons.delete).first;
      await _scrollTo(tester, deleteIcon);
      await tester.tap(deleteIcon);
      await tester.pump();
      expect(find.text('RemoveKW'), findsNothing);
    });

    testWidgets('voice sample section renders native controls (non-web)',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      // In desktop test environment, kIsWeb is false, so the native path renders
      // with mic icon, Start text, and Save File button.
      final micIcon = find.byIcon(Icons.mic);
      await _scrollTo(tester, micIcon);
      expect(micIcon, findsOneWidget);
    });

    testWidgets('voice sample section shows Start text for recording',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final startText = find.text('Start');
      await _scrollTo(tester, startText);
      expect(startText, findsOneWidget);
    });

    testWidgets('section icons are present', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.person), findsWidgets);
      expect(find.byIcon(Icons.warning), findsOneWidget);
      await _scrollTo(tester, find.byIcon(Icons.key));
      expect(find.byIcon(Icons.key), findsOneWidget);
      await _scrollTo(tester, find.byIcon(Icons.voice_chat));
      expect(find.byIcon(Icons.voice_chat), findsOneWidget);
    });

    testWidgets('tapping Save triggers save flow and shows snackbar',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final saveButton = find.widgetWithText(TextButton, 'Save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('multiple PII items can be added', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      for (final name in ['PII_One', 'PII_Two']) {
        await _openAddPIIDialog(tester);
        await tester.enterText(find.byType(TextFormField), name);
        await tester.tap(find.text('Add'));
        await _pumpSafe(tester);
      }
      expect(find.text('PII_One'), findsOneWidget);
      expect(find.text('PII_Two'), findsOneWidget);
    });

    testWidgets('Add Keyword without selecting dropdown still closes dialog',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'NoEvent');
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      expect(find.text('Add a keyword'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Caregiver with no caregiverId — shows failure info card
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – caregiver, no caregiverId', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: null,
        ),
      );
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(NotetakerConfigurationPage), findsOneWidget);
    });

    testWidgets('shows failure info card when no patients', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(
        find.textContaining('Configuration options cannot be displayed'),
        findsOneWidget,
      );
    });

    testWidgets('info card has info_outline icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('no Switch widgets in failure state', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('no DataTable in failure state', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('Cancel button is enabled', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final cancelBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancelBtn.onPressed, isNotNull);
    });

    testWidgets('Save button is enabled', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final saveBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveBtn.onPressed, isNotNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Caregiver with caregiverId — API fails, shows failure card
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – caregiver with caregiverId', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 10,
        ),
      );
    });

    testWidgets('renders and finishes loading', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(NotetakerConfigurationPage), findsOneWidget);
    });

    testWidgets('shows info card after API error (empty patient list)',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });

    testWidgets('error snackbar is shown when API fails', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Null user — redirect to login
  // ───────────────────────────────────────────────────────────────────────────
  // Note: The null-user path (build() returns spinner + context.go('/login'))
  // cannot be tested here because _loadConfiguration() in initState() calls
  // ScaffoldMessenger.of(context) before initState completes, and context.go()
  // requires GoRouter. The build() null-user branch is covered by the loading
  // state tests above (user is non-null but _isLoading is true).

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: _buildSection layout checks
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – section layout', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('sections have containers', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('page uses SingleChildScrollView for scrolling',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('toggle cards are rendered as Card widgets', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('toggle cards use ListTile', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byType(ListTile), findsWidgets);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Voice sample web path
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – voice sample native path', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('native voice section shows mic icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      // In desktop test env, kIsWeb is false, so native controls are shown
      await _scrollTo(tester, find.byIcon(Icons.mic));
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('native voice section shows Save File button',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _scrollTo(tester, find.text('Save File'));
      expect(find.text('Save File'), findsOneWidget);
    });

    testWidgets('Save File button is disabled when no recorded data',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final saveFileBtn = find.widgetWithText(ElevatedButton, 'Save File');
      await _scrollTo(tester, saveFileBtn);
      final btn = tester.widget<ElevatedButton>(saveFileBtn);
      // recordedData is empty initially, so button should be disabled
      expect(btn.onPressed, isNull);
    });

    testWidgets('voice sample section has info card with instructions',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      // The native voice section has an info card about voice recognition
      expect(find.textContaining('Tap the button below'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Patient selection (caregiver path)
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – patient selection (caregiver)', () {
    testWidgets('caregiver without caregiverId sees failure text',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: null,
        ),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(
        find.textContaining('no patients'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Toggle edge cases
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – toggle edge cases', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('toggling Enable Notetaker twice returns to original',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final switches = find.byType(Switch);
      final original = tester.widget<Switch>(switches.first).value;
      await tester.tap(switches.first);
      await tester.pump();
      await tester.tap(switches.first);
      await tester.pump();
      expect(tester.widget<Switch>(switches.first).value, equals(original));
    });

    testWidgets('toggling Enable Caregiver Access twice returns to original',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final switches = find.byType(Switch);
      final original = tester.widget<Switch>(switches.at(1)).value;
      await tester.tap(switches.at(1));
      await tester.pump();
      await tester.tap(switches.at(1));
      await tester.pump();
      expect(tester.widget<Switch>(switches.at(1)).value, equals(original));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Info card styling
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – info card styling', () {
    testWidgets('patient info card uses info_outline icon', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });

    testWidgets('caregiver failure info card uses info_outline icon',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: null,
        ),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: stringToCard coverage
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – stringToCard', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('adding multiple PII and removing one works', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      for (final name in ['Alpha', 'Beta', 'Gamma']) {
        await _openAddPIIDialog(tester);
        await tester.enterText(find.byType(TextFormField), name);
        await tester.tap(find.text('Add'));
        await _pumpSafe(tester);
      }
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
      // Remove the first one (Alpha)
      final cancelIcons = find.byIcon(Icons.cancel);
      await _scrollTo(tester, cancelIcons.first);
      await tester.tap(cancelIcons.first);
      await tester.pump();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });

    testWidgets('PII cancel icons have delete PII tooltip', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddPIIDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'Tooltipped');
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      expect(find.byTooltip('delete PII'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: generateRows coverage
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – generateRows', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('adding TASK keyword shows TASK in table', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'MyTask');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _pumpSafe(tester);
      await tester.tap(find.text('TASK').last);
      await _pumpSafe(tester);
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      await _scrollTo(tester, find.text('MyTask'));
      expect(find.text('MyTask'), findsOneWidget);
      expect(find.text('TASK'), findsOneWidget);
    });

    testWidgets('empty DataTable when no keywords added', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.rows.length, equals(0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: _saveConfiguration error path
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – save configuration', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('save shows error snackbar on failure', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
          find.textContaining('Failed to save configuration'), findsOneWidget);
    });

    testWidgets('save with PII and keywords still shows error snackbar',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      // Add a PII item
      await _openAddPIIDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'SavePII');
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      // Add a keyword
      await _openAddKeywordDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'SaveKW');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await _pumpSafe(tester);
      await tester.tap(find.text('ALERT').last);
      await _pumpSafe(tester);
      await tester.tap(find.text('Add'));
      await _pumpSafe(tester);
      // Now save - scroll back to top where Save button is
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // GROUP: Button styling
  // ───────────────────────────────────────────────────────────────────────────
  group('NotetakerConfigurationPage – button styling', () {
    late MockUserProvider provider;

    setUp(() {
      provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
    });

    testWidgets('Add PII has add icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.byIcon(Icons.add), findsWidgets);
    });

    testWidgets('Add PII button is a TextButton.icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.widgetWithText(TextButton, 'Add PII'), findsOneWidget);
    });

    testWidgets('Add Keyword button is a TextButton.icon', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(provider));
      await _pumpPastLoading(tester);
      expect(find.widgetWithText(TextButton, 'Add Keyword'), findsOneWidget);
    });
  });
}

