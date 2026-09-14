// Tests for NotetakerDetailView
// (lib/features/notetaker/presentation/notetaker_detail_view.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:care_connect_app/features/notetaker/presentation/notetaker_detail_view.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

import '../../mock_user_provider.dart';

/// A test note used across tests.
PatientNote _makeNote({
  String id = '42',
  String patientId = '1',
  String note = 'Test note content',
  String aiSummary = 'AI generated summary',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return PatientNote(
    id: id,
    patientId: patientId,
    note: note,
    aiSummary: aiSummary,
    createdAt: createdAt ?? DateTime(2025, 1, 15, 10, 30),
    updatedAt: updatedAt ?? DateTime(2025, 1, 16, 14, 0),
  );
}

/// Wraps NotetakerDetailView with no extra and no note id/patient context, so
/// the view renders its inline error state ("Invalid note ID or missing patient
/// context") instead of loading a note.
Widget _wrapNoExtra({MockUserProvider? provider}) {
  final userProvider =
      provider ?? MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            ChangeNotifierProvider<UserProvider>.value(
          value: userProvider,
          child: const NotetakerDetailView(),
        ),
      ),
      GoRoute(
        path: '/notetaker-search',
        builder: (context, state) =>
            const Scaffold(body: Text('Notetaker Search')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

/// Wraps NotetakerDetailView with a PatientNote as extra, using a sub-route
/// so that context.pop() has somewhere to go back to.
Widget _wrapWithNote({
  PatientNote? note,
  MockUserProvider? provider,
  ThemeData? theme,
}) {
  final userProvider =
      provider ?? MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
  final testNote = note ?? _makeNote();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Text('Home Page')),
        routes: [
          GoRoute(
            path: 'detail',
            builder: (context, state) =>
                ChangeNotifierProvider<UserProvider>.value(
              value: userProvider,
              child: const NotetakerDetailView(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/notetaker-search',
        builder: (context, state) =>
            const Scaffold(body: Text('Notetaker Search')),
      ),
    ],
  );

  // Navigate to the detail page with extra after building
  return _DetailViewLauncher(
    router: router,
    note: testNote,
    theme: theme,
  );
}

/// Helper widget that navigates to the detail view with extra data.
class _DetailViewLauncher extends StatefulWidget {
  final GoRouter router;
  final PatientNote note;
  final ThemeData? theme;

  const _DetailViewLauncher({
    required this.router,
    required this.note,
    this.theme,
  });

  @override
  State<_DetailViewLauncher> createState() => _DetailViewLauncherState();
}

class _DetailViewLauncherState extends State<_DetailViewLauncher> {
  @override
  void initState() {
    super.initState();
    // Navigate to detail after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.router.go('/home/detail', extra: widget.note);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: widget.router,
      theme: widget.theme,
    );
  }
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
        if (call.method == 'read') return null;
        if (call.method == 'write') return null;
        if (call.method == 'delete') return null;
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

  group('NotetakerDetailView - no extra (inline error)', () {
    testWidgets('shows the inline error when no note data is provided',
        (tester) async {
      await tester.pumpWidget(_wrapNoExtra());
      await tester.pump();
      expect(find.text('Invalid note ID or missing patient context'),
          findsWidgets);
    });

    testWidgets('does not navigate away when extra is null',
        (tester) async {
      await tester.pumpWidget(_wrapNoExtra());
      await tester.pump();
      await tester.pump();
      // Behavior changed from redirect-to-search to an inline error.
      expect(find.text('Notetaker Search'), findsNothing);
      expect(find.text('Invalid note ID or missing patient context'),
          findsWidgets);
    });
  });

  group('NotetakerDetailView - with PatientNote (PATIENT role)', () {
    testWidgets('renders AppBar with "Note Detail" title', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump(); // post-frame callback navigates
      await tester.pump(); // build detail view
      await tester.pump(); // settle
      expect(find.text('Note Detail'), findsOneWidget);
    });

    testWidgets('shows info card text', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('View and edit the details of this note.'),
          findsOneWidget);
    });

    testWidgets('shows info icon in info card', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('displays patient name as "Your Note" for PATIENT role',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Patient: Your Note'), findsOneWidget);
    });

    testWidgets('displays "Note Information" section', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note Information'), findsOneWidget);
    });

    testWidgets('displays note icon in Note Information section',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.note), findsOneWidget);
    });

    testWidgets('displays "AI Summary" section', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('AI Summary'), findsOneWidget);
    });

    testWidgets('displays smart_toy icon for AI Summary', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    testWidgets('displays "Note Content" section', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note Content'), findsOneWidget);
    });

    testWidgets('displays created date', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Created On:'), findsOneWidget);
      expect(find.textContaining('Jan 15, 2025'), findsOneWidget);
    });

    testWidgets('displays last updated date', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Last Updated:'), findsOneWidget);
      expect(find.textContaining('Jan 16, 2025'), findsOneWidget);
    });

    testWidgets('shows save icon in app bar when editing', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // When extra is a PatientNote, _isEditing is set to true
      expect(find.byIcon(Icons.save), findsOneWidget);
    });

    testWidgets('shows delete icon in app bar', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('shows back arrow in app bar', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows TextFields for note and AI summary when editing',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('note TextField contains note text', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Test note content'), findsOneWidget);
    });

    testWidgets('AI summary TextField contains AI summary text',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('AI generated summary'), findsOneWidget);
    });

    testWidgets('TextField hint text for note content', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      final note = _makeNote(note: '');
      await tester.pumpWidget(_wrapWithNote(note: note, provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Enter note content'), findsOneWidget);
    });

    testWidgets('SingleChildScrollView is present', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('NotetakerDetailView - editing interactions', () {
    testWidgets('typing in note field updates text', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final noteFields = find.byType(TextField);
      expect(noteFields, findsNWidgets(2));

      await tester.enterText(noteFields.last, 'Updated note text');
      await tester.pump();
      expect(find.text('Updated note text'), findsOneWidget);
    });

    testWidgets('typing in AI summary field updates text', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'Updated AI summary');
      await tester.pump();
      expect(find.text('Updated AI summary'), findsOneWidget);
    });
  });

  group('NotetakerDetailView - delete dialog', () {
    testWidgets('tapping delete shows confirmation dialog', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The delete icon may be off-screen in the AppBar, so invoke via widget callback.
      final deleteButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete),
      );
      deleteButton.onPressed!();
      await tester.pump();

      expect(find.text('Delete Note'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this note?'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('cancel button dismisses delete dialog', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final deleteButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete),
      );
      deleteButton.onPressed!();
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(
          find.text('Are you sure you want to delete this note?'), findsNothing);
    });

    testWidgets('confirm delete triggers delete (HTTP fails gracefully)',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final deleteButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete),
      );
      deleteButton.onPressed!();
      await tester.pump();

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('NotetakerDetailView - CAREGIVER role', () {
    testWidgets(
        'shows content after loading fails for CAREGIVER (fallback name)',
        (tester) async {
      final provider = MockUserProvider(
        mockUser:
            MockUser(role: 'CAREGIVER', caregiverId: 10, patientId: null),
      );
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // Let the HTTP call fail and settle
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      // After failure, _patientName = 'Unknown Patient'
      expect(find.textContaining('Unknown Patient'), findsOneWidget);
    });
  });

  group('NotetakerDetailView - null user in provider', () {
    testWidgets('handles null user gracefully (no patient name shown)',
        (tester) async {
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(_wrapWithNote(provider: nullProvider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // _fetchPatientName returns early when user is null
      expect(find.text('Note Detail'), findsOneWidget);
      expect(find.text('Note Information'), findsOneWidget);
    });
  });

  group('NotetakerDetailView - PopScope and unsaved changes', () {
    testWidgets('back button works when no changes made', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      // Should NOT show unsaved changes dialog
      expect(find.text('Unsaved Changes'), findsNothing);
    });

    testWidgets('back button shows unsaved changes dialog when text changed',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final noteFields = find.byType(TextField);
      await tester.enterText(noteFields.last, 'Modified text');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(find.text('Unsaved Changes'), findsOneWidget);
      expect(
          find.text('You have unsaved changes. Do you want to save them?'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('cancel in unsaved changes dialog dismisses dialog',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final noteFields = find.byType(TextField);
      await tester.enterText(noteFields.last, 'Changed text');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(find.text('Note Detail'), findsOneWidget);
    });

    testWidgets('discard in unsaved changes dialog pops back',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final noteFields = find.byType(TextField);
      await tester.enterText(noteFields.last, 'Changed again');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump();

      // Should navigate back - dialog dismissed at minimum
      expect(find.text('Unsaved Changes'), findsNothing);
    });

    testWidgets('changing AI summary also triggers hasChanges',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'New AI summary');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(find.text('Unsaved Changes'), findsOneWidget);
    });
  });

  group('NotetakerDetailView - save button', () {
    testWidgets('tapping save icon triggers save (HTTP fails gracefully)',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Save icon may be off-screen, so invoke via widget callback.
      final saveButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.save),
      );
      saveButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('NotetakerDetailView - save from unsaved dialog', () {
    testWidgets(
        'save option in unsaved changes dialog triggers save',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.last, 'Some changes');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(find.text('Unsaved Changes'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });
  });

  group('NotetakerDetailView - with different note data', () {
    testWidgets('displays custom note content', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      final customNote = _makeNote(
        note: 'Custom patient observations',
        aiSummary: 'Custom AI analysis of the session',
      );
      await tester.pumpWidget(
          _wrapWithNote(note: customNote, provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Custom patient observations'), findsOneWidget);
      expect(find.text('Custom AI analysis of the session'), findsOneWidget);
    });

    testWidgets('displays different dates correctly', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      final customNote = _makeNote(
        createdAt: DateTime(2024, 12, 25, 9, 0),
        updatedAt: DateTime(2025, 3, 1, 15, 30),
      );
      await tester.pumpWidget(
          _wrapWithNote(note: customNote, provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Dec 25, 2024'), findsOneWidget);
      expect(find.textContaining('Mar 01, 2025'), findsOneWidget);
    });
  });

  group('NotetakerDetailView - theme and styling', () {
    testWidgets('renders in dark theme without errors', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(
          _wrapWithNote(provider: provider, theme: ThemeData.dark()));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note Detail'), findsOneWidget);
      expect(find.text('Note Information'), findsOneWidget);
    });

    testWidgets('has three section titles', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note Information'), findsOneWidget);
      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text('Note Content'), findsOneWidget);
    });

    testWidgets('edit icon in Note Content section is present',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  group('NotetakerDetailView - edge cases', () {
    testWidgets('empty note content displays correctly', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      final emptyNote = _makeNote(note: '', aiSummary: '');
      await tester.pumpWidget(
          _wrapWithNote(note: emptyNote, provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Note Detail'), findsOneWidget);
      expect(find.text('Enter note content'), findsOneWidget);
    });

    testWidgets('very long text in note renders without overflow',
        (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      final longText = 'A' * 500;
      final longNote = _makeNote(note: longText);
      await tester.pumpWidget(
          _wrapWithNote(note: longNote, provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(longText), findsOneWidget);
    });

    testWidgets('widget disposes without error', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));
      await tester.pumpWidget(_wrapWithNote(provider: provider));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Replaced'))));
      await tester.pump();
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets('no patient name shown when user is null', (tester) async {
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(_wrapWithNote(provider: nullProvider));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // Patient name should not appear since user is null
      expect(find.textContaining('Patient:'), findsNothing);
      expect(find.text('Note Information'), findsOneWidget);
    });
  });
}

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}
