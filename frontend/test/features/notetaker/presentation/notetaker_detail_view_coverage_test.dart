// Additional coverage for NotetakerDetailView
// (lib/features/notetaker/presentation/notetaker_detail_view.dart):
// deep-link loading, caregiver name lookup success, save success,
// read-only rendering, delete failure, and system back via PopScope.

import 'dart:convert';

import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:care_connect_app/features/notetaker/presentation/notetaker_detail_view.dart';
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

PatientNote _note({String patientId = '1'}) => PatientNote(
      id: '42',
      patientId: patientId,
      note: 'Original note body',
      aiSummary: 'Original AI summary',
      createdAt: DateTime(2025, 1, 15, 10, 30),
      updatedAt: DateTime(2025, 1, 16, 14, 0),
    );

Map<String, dynamic> _noteJson({
  String id = '42',
  String note = 'Saved note body',
  String summary = 'Saved AI summary',
}) =>
    {
      'id': id,
      'patientId': '1',
      'note': note,
      'aiSummary': summary,
      'createdAt': '2025-01-15T10:30:00.000',
      'updatedAt': '2025-01-17T09:00:00.000',
    };

/// Router with a home page and a detail sub-route. When [deepLink] is set,
/// the app starts there; otherwise it navigates to the detail page with
/// [extra] after the first frame.
Widget _app({
  required UserProvider provider,
  PatientNote? extra,
  String? deepLink,
}) {
  final router = GoRouter(
    initialLocation: deepLink ?? '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('Home Page')),
        routes: [
          GoRoute(
            path: 'detail',
            builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
              value: provider,
              child: const NotetakerDetailView(),
            ),
          ),
          GoRoute(
            path: 'note/:noteId',
            builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
              value: provider,
              child: const NotetakerDetailView(),
            ),
          ),
        ],
      ),
    ],
  );
  if (extra != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go('/home/detail', extra: extra);
    });
  }
  return MaterialApp.router(routerConfig: router);
}

Future<void> _settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  tearDown(() {
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

  group('deep link loading', () {
    testWidgets('loads the note by id when patientId query is present',
        (tester) async {
      final requested = <String>[];
      final client = MockClient((req) async {
        requested.add(req.url.path);
        return http.Response(jsonEncode(_noteJson(id: 'n1')), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
          deepLink: '/home/note/n1?patientId=7',
        ));
        await _settle(tester);
      }, () => client);

      expect(requested.single, endsWith('/7/notes/n1'));
      expect(find.text('Patient: Your Note'), findsOneWidget);
      expect(find.text('Saved note body'), findsOneWidget);
      expect(find.text('Saved AI summary'), findsOneWidget);
    });

    testWidgets('shows an error when the note cannot be loaded',
        (tester) async {
      final client = MockClient((_) async => http.Response('nope', 404));
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
          deepLink: '/home/note/missing?patientId=7',
        ));
        await _settle(tester);
      }, () => client);

      expect(find.text('Could not load note missing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('caregiver patient name', () {
    testWidgets('resolves the patient name from caregiver patients',
        (tester) async {
      ApiService.debugSetHttpClient(MockClient((req) async {
        return http.Response(
          jsonEncode([
            {
              'patient': {'id': 1, 'firstName': 'Jane', 'lastName': 'Doe'},
            },
          ]),
          200,
        );
      }));
      await tester.pumpWidget(_app(
        provider: MockUserProvider(
          mockUser: MockUser(role: 'CAREGIVER', caregiverId: 3, patientId: null),
        ),
        extra: _note(),
      ));
      await _settle(tester);

      expect(find.text('Patient: Jane Doe'), findsOneWidget);
    });

    testWidgets('falls back to Unknown Patient when not in the list',
        (tester) async {
      ApiService.debugSetHttpClient(MockClient((req) async {
        return http.Response(
          jsonEncode([
            {
              'patient': {'id': 99, 'firstName': 'Other', 'lastName': 'One'},
            },
          ]),
          200,
        );
      }));
      await tester.pumpWidget(_app(
        provider: MockUserProvider(
          mockUser: MockUser(role: 'CAREGIVER', caregiverId: 3, patientId: null),
        ),
        extra: _note(),
      ));
      await _settle(tester);

      expect(find.text('Patient: Unknown Patient'), findsOneWidget);
    });
  });

  group('save, read-only mode and delete failure', () {
    testWidgets('successful save shows snackbar and read-only view',
        (tester) async {
      String? putBody;
      final client = MockClient((req) async {
        if (req.method == 'PUT') {
          putBody = req.body;
          return http.Response(jsonEncode(_noteJson()), 200);
        }
        return http.Response('{}', 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(
          provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
          extra: _note(),
        ));
        await _settle(tester);

        await tester.enterText(find.byType(TextField).last, 'Edited body');
        await tester.pump();

        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.save))
            .onPressed!();
        // Let the save complete; the page rebuilds in read-only mode while
        // its pop transition is still running.
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }

        expect(putBody, contains('Edited body'));
        expect(find.text('Note saved successfully'), findsOneWidget);
        expect(find.widgetWithIcon(IconButton, Icons.edit), findsOneWidget);
        expect(find.text('Saved AI summary'), findsOneWidget);
        expect(find.text('Saved note body'), findsOneWidget);

        // Edit button switches back to editing mode.
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.edit))
            .onPressed!();
        await tester.pump();
        expect(find.widgetWithIcon(IconButton, Icons.save), findsOneWidget);

        await tester.pump(const Duration(seconds: 1));
      }, () => client);
      expect(find.text('Home Page'), findsOneWidget);
    });

    testWidgets('delete failure shows an error snackbar', (tester) async {
      await tester.pumpWidget(_app(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
        // Non-numeric patient id makes int.parse throw inside _deleteNote.
        extra: _note(patientId: 'abc'),
      ));
      await _settle(tester);

      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete))
          .onPressed!();
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await _settle(tester);

      expect(find.textContaining('Failed to delete note:'), findsOneWidget);
      expect(find.text('Note Detail'), findsOneWidget);
    });
  });

  group('system back', () {
    testWidgets('system back without changes pops the page', (tester) async {
      await tester.pumpWidget(_app(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
        extra: _note(),
      ));
      await _settle(tester);
      expect(find.text('Note Detail'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Home Page'), findsOneWidget);
      expect(find.text('Note Detail'), findsNothing);
    });
  });
}
