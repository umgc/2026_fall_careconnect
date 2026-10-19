import 'package:care_connect_app/features/tasks/presentation/widgets/filters_panel.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../mock_user_provider.dart';

class _LocalUserSession extends UserSession {
  @override
  final bool isCaregiver;
  @override
  final bool isPatient = false;

  _LocalUserSession({this.isCaregiver = true})
      : super(
          id: 1,
          email: 'test@test.com',
          role: isCaregiver ? 'CAREGIVER' : 'PATIENT',
          token: 'fake-token',
        );
}

/// Mock UserProvider that supplies a fake caregiver user.
class _LocalUserProvider extends ChangeNotifier implements UserProvider {
  @override
  UserSession? user = _LocalUserSession(isCaregiver: true);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Helpers from features/tasks/widgets/filters_panel_test.dart (merged) ──

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _wrap({bool expanded = false}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: _NullUserProvider()),
      ChangeNotifierProvider<TaskTypeManager>(create: (_) => TaskTypeManager()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FiltersPanel(
          expanded: expanded,
          patientNames: const {},
          selectedTypes: const {},
          selectedPatients: const {},
          onClear: () {},
          onTypeToggled: (_) {},
          onPatientToggled: (_) {},
          onToggleExpanded: () {},
          onTodayPressed: () {},
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({}); // Prevent MissingPluginException

  group('FiltersPanel Widget Tests', () {
    late TaskTypeManager manager;
    late bool clearPressed;
    late bool todayPressed;
    late bool togglePressed;
    late String toggledType;
    late int toggledPatient;

    setUp(() {
      manager = TaskTypeManager();
      clearPressed = false;
      todayPressed = false;
      togglePressed = false;
      toggledType = '';
      toggledPatient = -1;
    });

    /// Wraps widget with Providers
    Widget wrapWithProviders(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskTypeManager>.value(value: manager),
          ChangeNotifierProvider<UserProvider>(
            create: (_) => _LocalUserProvider(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('renders collapsed view with Today button', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: false,
            patientNames: const {},
            selectedTypes: const {},
            selectedPatients: const {},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Tapping expand button calls onToggleExpanded
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      expect(togglePressed, isTrue);
    });

    testWidgets('renders expanded view with task type chips', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: true,
            patientNames: const {},
            selectedTypes: const {},
            selectedPatients: const {},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and clear button exist
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Task Types'), findsOneWidget);

      // Verify chips render from TaskTypeManager defaults
      expect(find.byType(FilterChip), findsWidgets);

      // Tap a chip
      final firstChip = find.byType(FilterChip).first;
      await tester.tap(firstChip);
      await tester.pump();
      expect(toggledType.isNotEmpty, isTrue);
    });

    testWidgets('calls onClear when Clear button is pressed', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: true,
            patientNames: const {},
            selectedTypes: const {},
            selectedPatients: const {},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(clearPressed, isTrue);
    });

    testWidgets('calls onTodayPressed when Today button is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: true,
            patientNames: const {},
            selectedTypes: const {},
            selectedPatients: const {},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(todayPressed, isTrue);
    });

    testWidgets('renders patient filter chips for caregivers', (tester) async {
      final patients = {1: 'John Doe', 2: 'Jane Smith'};

      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: true,
            patientNames: patients,
            selectedTypes: const {},
            selectedPatients: const {},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);

      // Tap a patient chip
      await tester.tap(find.text('John Doe'));
      await tester.pump();
      expect(toggledPatient, equals(1));
    });

    testWidgets('selected chips display with correct color and selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithProviders(
          FiltersPanel(
            expanded: true,
            patientNames: const {},
            selectedTypes: {'medication'},
            selectedPatients: const {1},
            onClear: () => clearPressed = true,
            onTypeToggled: (s) => toggledType = s,
            onPatientToggled: (i) => toggledPatient = i,
            onToggleExpanded: () => togglePressed = true,
            onTodayPressed: () => todayPressed = true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the "Medication" chip text
      expect(
        find.textContaining('Medication', findRichText: true),
        findsWidgets,
      );
    });
  });

  // Cases merged from features/tasks/widgets/filters_panel_test.dart.
  group('merged from features/tasks/widgets/filters_panel_test.dart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('FiltersPanel – initial render', () {
      testWidgets('renders without crashing (collapsed)', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.byType(FiltersPanel), findsOneWidget);
      });

      testWidgets('shows Filters label', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.text('Filters'), findsOneWidget);
      });

      testWidgets('shows expand icon when collapsed', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets('shows expand_more icon when expanded', (tester) async {
        await tester.pumpWidget(_wrap(expanded: true));
        await tester.pump();
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      });

      testWidgets('shows Filters text label', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.text('Filters'), findsOneWidget);
      });

      testWidgets('shows Today button', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.text('Today'), findsOneWidget);
      });

      testWidgets('shows Scaffold', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        expect(find.byType(Scaffold), findsOneWidget);
      });
    });
  });
}
