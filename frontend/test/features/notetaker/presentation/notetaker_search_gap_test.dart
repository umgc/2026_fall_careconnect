// Gap-filling widget tests for NotetakerSearchPage
// (lib/features/notetaker/presentation/notetaker_search.dart).
//
// notetaker_search_test.dart covers initial rendering, text search and basic
// navigation. This file covers what it leaves out: choosing start/end dates
// in the real date picker and the resulting list filtering, refreshing notes
// when the detail page returns true, caregiver patient loading failures and
// patient selection, and the callbacks the page hands to the recording widget
// (upload success -> AI task snackbar, upload error -> error snackbar).
//
// HTTP is faked with a MockClient (no live network). The page's init() runs
// from initState, so the framework's initState-lifecycle assertions are
// filtered exactly as the sibling test file does.

import 'dart:convert';

import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:care_connect_app/features/notetaker/presentation/notetaker_search.dart';
import 'package:care_connect_app/features/streaming_asr_with_diarization/streaming_asr_and_diarization.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

final _notes = [
  {
    'id': '1',
    'patientId': '1',
    'note': 'n1',
    'aiSummary': 'Headache reported during visit',
    'createdAt': '2025-03-10T12:00:00.000',
    'updatedAt': '2025-03-10T12:00:00.000',
  },
  {
    'id': '2',
    'patientId': '1',
    'note': 'n2',
    'aiSummary': 'Medication follow-up completed',
    'createdAt': '2025-03-12T12:00:00.000',
    'updatedAt': '2025-03-12T12:00:00.000',
  },
  {
    'id': '3',
    'patientId': '1',
    'note': 'n3',
    'aiSummary': 'Annual checkup completed',
    'createdAt': '2025-02-01T12:00:00.000',
    'updatedAt': '2025-02-01T12:00:00.000',
  },
];

final _caregiverPatients = [
  {
    'patient': {'id': 10, 'firstName': 'Jane', 'lastName': 'Doe'},
  },
  {
    'patient': {'id': 20, 'firstName': 'John', 'lastName': 'Smith'},
  },
];

/// Requests seen by the fake backend, as "METHOD url".
final List<String> _requests = <String>[];

/// Overridable per test.
int _patientsStatus = 200;
String _patientsBody = jsonEncode(_caregiverPatients);
int _tasksStatus = 200;
int _taskAgeMs = 0;

MockClient _client() => MockClient((request) async {
      final url = request.url.toString();
      _requests.add('${request.method} $url');
      if (url.contains('/notes')) {
        return http.Response(jsonEncode(_notes), 200);
      }
      if (url.contains('caregivers') && url.contains('patients')) {
        return http.Response(_patientsBody, _patientsStatus);
      }
      if (url.contains('tasks')) {
        final created = DateTime.now().millisecondsSinceEpoch - _taskAgeMs;
        return http.Response(
          jsonEncode([
            {
              'id': 5,
              'name': 'Refill prescription',
              'date': '2025-03-12T09:00:00',
              'createdAt': created,
              'patientId': 1,
            },
          ]),
          _tasksStatus,
        );
      }
      return http.Response('{}', 200);
    });

Widget _wrap({
  int? patientId = 1,
  String role = 'PATIENT',
  int? caregiverId,
}) {
  final provider = MockUserProvider(
    mockUser: MockUser(
      id: 1,
      role: role,
      patientId: patientId,
      caregiverId: caregiverId,
    ),
  );
  return MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
            value: provider,
            child: const NotetakerSearchPage(),
          ),
        ),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold()),
        GoRoute(
          path: '/notetaker/detail/:id',
          builder: (context, __) => Scaffold(
            body: ElevatedButton(
              onPressed: () => context.pop(true),
              child: const Text('Back with changes'),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _load(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpPage(
  WidgetTester tester, {
  int? patientId = 1,
  String role = 'PATIENT',
  int? caregiverId,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(
        _wrap(patientId: patientId, role: role, caregiverId: caregiverId));
    await _load(tester);
  }, _client);
}

/// Opens the date picker behind [buttonLabel], types [mmddyyyy] into its text
/// field and confirms with OK.
Future<void> _pickDate(
    WidgetTester tester, String buttonLabel, String mmddyyyy) async {
  await tester.ensureVisible(find.text(buttonLabel));
  await tester.pump();
  await tester.tap(find.text(buttonLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, mmddyyyy);
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  final originalOnError = FlutterError.onError;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _requests.clear();
    _patientsStatus = 200;
    _patientsBody = jsonEncode(_caregiverPatients);
    _tasksStatus = 200;
    _taskAgeMs = 0;
    ApiService.debugSetHttpClient(_client());
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        if (call.method == 'read') return 'mock_token';
        return null;
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    // init() runs from initState; filter the same framework lifecycle
    // assertions that the sibling test file filters.
    FlutterError.onError = (details) {
      final msg = details.toString();
      if (msg.contains('overflowed') ||
          msg.contains('dependOnInheritedWidgetOfExactType') ||
          msg.contains('dependOnInheritedElement') ||
          msg.contains('initState() completed')) {
        return;
      }
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    ApiService.debugResetHttpClient();
  });

  group('date filtering', () {
    testWidgets('start date hides notes created before it', (tester) async {
      await _pumpPage(tester);
      expect(find.text('Headache reported during visit'), findsOneWidget);

      await _pickDate(tester, 'Start Date', '03/11/2025');

      expect(find.text('Start: 2025-03-11'), findsOneWidget);
      expect(find.text('Medication follow-up completed'), findsOneWidget);
      expect(find.text('Headache reported during visit'), findsNothing);
      expect(find.text('Annual checkup completed'), findsNothing);
    });

    testWidgets('end date hides notes created after it', (tester) async {
      await _pumpPage(tester);

      await _pickDate(tester, 'End Date', '03/10/2025');

      expect(find.text('End: 2025-03-10'), findsOneWidget);
      expect(find.text('Headache reported during visit'), findsOneWidget);
      expect(find.text('Annual checkup completed'), findsOneWidget);
      expect(find.text('Medication follow-up completed'), findsNothing);
    });

    testWidgets('a range with no notes shows the empty state and Clear resets',
        (tester) async {
      await _pumpPage(tester);

      await _pickDate(tester, 'Start Date', '03/11/2025');
      await _pickDate(tester, 'End Date', '03/11/2025');
      expect(find.text('No notes found'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pump();

      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      expect(find.text('No notes found'), findsNothing);
      expect(find.text('Headache reported during visit'), findsOneWidget);
      expect(find.text('Medication follow-up completed'), findsOneWidget);
      expect(find.text('Annual checkup completed'), findsOneWidget);
    });

    testWidgets('search text and a date range combine', (tester) async {
      await _pumpPage(tester);

      await _pickDate(tester, 'Start Date', '03/01/2025');
      await tester.enterText(
          find.widgetWithText(TextField, 'Search notes'), 'completed');
      await tester.pump();

      expect(find.text('Medication follow-up completed'), findsOneWidget);
      expect(find.text('Annual checkup completed'), findsNothing);
      expect(find.text('Headache reported during visit'), findsNothing);
    });

    testWidgets('cancelling the picker leaves the filter unchanged',
        (tester) async {
      await _pumpPage(tester);
      await tester.ensureVisible(find.text('Start Date'));
      await tester.pump();
      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('Annual checkup completed'), findsOneWidget);
    });
  });

  group('note detail', () {
    testWidgets('returning true from the detail page reloads the notes',
        (tester) async {
      await _pumpPage(tester);
      int notesCalls() => _requests.where((r) => r.contains('/notes')).length;
      expect(notesCalls(), 1);

      await http.runWithClient(() async {
        await tester.ensureVisible(find.text('Headache reported during visit'));
        await tester.pump();
        await tester.tap(find.text('Headache reported during visit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back with changes'));
        await tester.pumpAndSettle();
      }, _client);

      expect(notesCalls(), 2);
      expect(find.text('Headache reported during visit'), findsOneWidget);
    });
  });

  group('caregiver', () {
    testWidgets('patient list failure shows a profile error and info card',
        (tester) async {
      _patientsBody = jsonEncode({'error': 'boom'});
      _patientsStatus = 500;
      await _pumpPage(tester,
          role: 'CAREGIVER', patientId: null, caregiverId: 5);

      expect(
          find.textContaining('Failed to load user profile'), findsOneWidget);
      expect(
          find.text('Error fetching Medical Notetaker Notes.'), findsOneWidget);
      expect(find.text('Patient Notes'), findsNothing);
    });

    testWidgets('choosing a patient loads that patient\'s notes',
        (tester) async {
      await _pumpPage(tester,
          role: 'CAREGIVER', patientId: null, caregiverId: 5);
      expect(find.text('Select patient'), findsOneWidget);
      expect(find.text('Patient Notes'), findsNothing);

      await http.runWithClient(() async {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('John Smith').last);
        await tester.pump();
        await _load(tester);
      }, _client);

      expect(_requests.any((r) => r.contains('/20/notes')), isTrue);
      expect(find.text('Patient Notes'), findsOneWidget);
      expect(find.text('Record A Note'), findsOneWidget);
      expect(find.text('Headache reported during visit'), findsOneWidget);
    });
  });

  group('recording callbacks', () {
    PatientNote newNote() => PatientNote(
          id: '99',
          patientId: '1',
          note: 'raw',
          aiSummary: 'Freshly dictated note',
          createdAt: DateTime(2025, 4, 1, 12),
          updatedAt: DateTime(2025, 4, 1, 12),
        );

    StreamingAsrAndDiarizationScreen screen(WidgetTester tester) =>
        tester.widget<StreamingAsrAndDiarizationScreen>(
            find.byType(StreamingAsrAndDiarizationScreen));

    testWidgets('upload success lists the note and announces an AI task',
        (tester) async {
      await _pumpPage(tester);
      expect(find.text('Freshly dictated note'), findsNothing);

      await http.runWithClient(() async {
        screen(tester).onUploadSuccess!(newNote());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
      }, _client);

      expect(find.text('Freshly dictated note'), findsOneWidget);
      expect(_requests.any((r) => r.contains('tasks')), isTrue);
      expect(find.text('AI Generated A Task From Your Notes'), findsOneWidget);
    });

    testWidgets('no snackbar when the AI task is old', (tester) async {
      _taskAgeMs = 10 * 60 * 1000;
      await _pumpPage(tester);

      await http.runWithClient(() async {
        screen(tester).onUploadSuccess!(newNote());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
      }, _client);

      expect(_requests.any((r) => r.contains('tasks')), isTrue);
      expect(find.text('AI Generated A Task From Your Notes'), findsNothing);
    });

    testWidgets('no snackbar when the task lookup fails', (tester) async {
      _tasksStatus = 500;
      await _pumpPage(tester);

      await http.runWithClient(() async {
        screen(tester).onUploadSuccess!(newNote());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
      }, _client);

      expect(_requests.any((r) => r.contains('tasks')), isTrue);
      expect(find.text('AI Generated A Task From Your Notes'), findsNothing);
    });

    testWidgets('upload error is shown in a snackbar', (tester) async {
      await _pumpPage(tester);

      screen(tester).onUploadError!('Upload rejected by server');
      await tester.pump();

      expect(find.text('Upload rejected by server'), findsOneWidget);
    });
  });
}
