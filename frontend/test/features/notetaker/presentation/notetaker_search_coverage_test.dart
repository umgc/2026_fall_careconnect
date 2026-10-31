// Additional coverage for NotetakerSearchPage
// (lib/features/notetaker/presentation/notetaker_search.dart):
// init error paths, date-range filtering, detail round-trip refresh,
// upload callbacks and the AI-task check after an upload.

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

const _successText =
    'View, Edit, and Delete your Notes from Notetaker Assistant.';

final _notes = [
  {
    'id': '1',
    'patientId': '1',
    'note': 'n1',
    'aiSummary': 'Headache reported during visit',
    'createdAt': '2025-03-10T10:00:00.000',
    'updatedAt': '2025-03-10T10:00:00.000',
  },
  {
    'id': '2',
    'patientId': '1',
    'note': 'n2',
    'aiSummary': 'Medication follow-up completed',
    'createdAt': '2025-03-12T14:00:00.000',
    'updatedAt': '2025-03-12T14:00:00.000',
  },
];

/// Client used for NotetakerConfigService (top-level http.get, zone client).
MockClient _notesClient({void Function()? onNotes}) => MockClient((req) async {
      if (req.url.path.endsWith('/notes')) {
        onNotes?.call();
        return http.Response(jsonEncode(_notes), 200);
      }
      return http.Response('[]', 200);
    });

Widget _app(UserProvider provider) {
  final router = GoRouter(
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
          body: TextButton(
            onPressed: () => context.pop(true),
            child: const Text('Done Editing'),
          ),
        ),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

MockUserProvider _patient({int? patientId = 1}) => MockUserProvider(
      mockUser: MockUser(role: 'PATIENT', patientId: patientId),
    );

Future<void> _settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _today() => DateTime.now().toString().split(' ')[0];

void main() {
  final originalOnError = FlutterError.onError;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        if (call.method == 'read') return 'mock_token';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    ApiService.debugResetHttpClient();
  });

  testWidgets('patient without patientId stops loading and filters safely',
      (tester) async {
    await tester.pumpWidget(_app(_patient(patientId: null)));
    await _settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes found'), findsOneWidget);

    // _filterNotes with no loaded notes keeps the list empty.
    await tester.enterText(
        find.widgetWithText(TextField, 'Search notes'), 'anything');
    await tester.pump();
    expect(find.text('No notes found'), findsOneWidget);
  });

  testWidgets('caregiver patient list decode failure shows snackbar',
      (tester) async {
    ApiService.debugSetHttpClient(
      MockClient((_) async => http.Response('{"not":"a list"}', 200)),
    );
    await tester.pumpWidget(_app(MockUserProvider(
      mockUser: MockUser(role: 'CAREGIVER', caregiverId: 5, patientId: null),
    )));
    await _settle(tester);

    expect(find.textContaining('Failed to load user profile:'), findsOneWidget);
    expect(find.text('Error fetching Medical Notetaker Notes.'), findsOneWidget);
  });

  testWidgets('caregiver dropdown validator requires a selection',
      (tester) async {
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
          jsonEncode([
            {
              'patient': {'id': 10, 'firstName': 'Jane', 'lastName': 'Doe'},
            },
          ]),
          200,
        )));
    await tester.pumpWidget(_app(MockUserProvider(
      mockUser: MockUser(role: 'CAREGIVER', caregiverId: 5, patientId: null),
    )));
    await _settle(tester);

    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.validator!(null), 'Please select an option');
    expect(field.validator!('10'), isNull);
  });

  testWidgets('start and end date pickers filter the notes', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_patient()));
      await _settle(tester);
      expect(find.text('Headache reported during visit'), findsOneWidget);

      // End date = today keeps every (past) note.
      await tester.ensureVisible(find.text('End Date'));
      await tester.tap(find.text('End Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('End: ${_today()}'), findsOneWidget);
      expect(find.text('Headache reported during visit'), findsOneWidget);
      expect(find.text('Medication follow-up completed'), findsOneWidget);

      // Start date = today removes all 2025 notes.
      await tester.ensureVisible(find.text('Start Date'));
      await tester.tap(find.text('Start Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Start: ${_today()}'), findsOneWidget);
      expect(find.text('No notes found'), findsOneWidget);

      // Cancelling a picker leaves the filter unchanged.
      await tester.tap(find.text('Start: ${_today()}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Start: ${_today()}'), findsOneWidget);
    }, () => _notesClient());
  });

  testWidgets('returning true from the detail page reloads notes',
      (tester) async {
    var fetches = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_patient()));
      await _settle(tester);
      expect(fetches, 1);

      await tester.ensureVisible(find.text('Headache reported during visit'));
      await tester.tap(find.text('Headache reported during visit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done Editing'));
      await tester.pumpAndSettle();

      expect(fetches, 2);
      expect(find.text('Headache reported during visit'), findsOneWidget);
    }, () => _notesClient(onNotes: () => fetches++));
  });

  testWidgets('upload success adds the note and announces a recent AI task',
      (tester) async {
    final taskRequests = <String>[];
    ApiService.debugSetHttpClient(MockClient((req) async {
      taskRequests.add(req.url.path);
      final now = DateTime.now().millisecondsSinceEpoch;
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'name': 'Old task',
            'date': '2025-03-10 09:00:00',
            'createdAt': now - 3600000,
          },
          {'id': 2, 'name': 'Broken task'}, // no date -> parse error
          {
            'id': 3,
            'name': 'Fresh task',
            'date': '2025-03-11T09:00:00',
            'createdAt': now,
          },
        ]),
        200,
      );
    }));
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_patient()));
      await _settle(tester);

      final screen = tester.widget<StreamingAsrAndDiarizationScreen>(
        find.byType(StreamingAsrAndDiarizationScreen),
      );
      screen.onUploadSuccess!(PatientNote(
        id: '9',
        patientId: '1',
        note: 'new',
        aiSummary: 'Brand new uploaded summary',
        createdAt: DateTime(2025, 4, 1),
        updatedAt: DateTime(2025, 4, 1),
      ));
      await _settle(tester);

      expect(find.text('Brand new uploaded summary'), findsOneWidget);
      expect(taskRequests.single, endsWith('/patient/1'));
      expect(find.text('AI Generated A Task From Your Notes'), findsOneWidget);
    }, () => _notesClient());
  });

  testWidgets('upload success with failing task fetch shows no AI snackbar',
      (tester) async {
    ApiService.debugSetHttpClient(
      MockClient((_) async => http.Response('err', 500)),
    );
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_patient()));
      await _settle(tester);

      final screen = tester.widget<StreamingAsrAndDiarizationScreen>(
        find.byType(StreamingAsrAndDiarizationScreen),
      );
      screen.onUploadSuccess!(PatientNote(
        id: '9',
        patientId: '1',
        note: 'new',
        aiSummary: 'Another upload',
        createdAt: DateTime(2025, 4, 1),
        updatedAt: DateTime(2025, 4, 1),
      ));
      await _settle(tester);

      expect(find.text('Another upload'), findsOneWidget);
      expect(find.text('AI Generated A Task From Your Notes'), findsNothing);
    }, () => _notesClient());
  });

  testWidgets('upload error shows the error in a snackbar', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(_patient()));
      await _settle(tester);

      tester
          .widget<StreamingAsrAndDiarizationScreen>(
            find.byType(StreamingAsrAndDiarizationScreen),
          )
          .onUploadError!('Upload exploded');
      await tester.pump();

      expect(find.text('Upload exploded'), findsOneWidget);
      expect(find.text(_successText), findsOneWidget);
    }, () => _notesClient());
  });
}
