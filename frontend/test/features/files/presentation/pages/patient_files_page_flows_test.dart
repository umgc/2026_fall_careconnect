// Flow tests for PatientFilesPage
// (lib/features/files/presentation/pages/patient_files_page.dart) with a
// populated file list: category filter, preview/download, delete and the
// structured-entry menu item. EnhancedFileService uses package:http top-level
// calls, so bodies run inside http.runWithClient with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/features/files/presentation/pages/patient_files_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/structured_entry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

final _files = [
  {
    'id': 1,
    'originalFilename': 'visit_note.pdf',
    'filename': 'visit_note.pdf',
    'contentType': 'application/pdf',
    'fileSize': 900,
    'fileCategory': 'MEDICAL_NOTE',
    'description': 'Follow-up visit',
  },
  {
    'id': 2,
    'originalFilename': 'rash.png',
    'filename': 'rash.png',
    'contentType': 'image/png',
    'fileSize': 5000,
    'fileCategory': 'LAB_RESULT',
  },
  {
    'id': 3,
    'originalFilename': 'contacts.txt',
    'filename': 'contacts.txt',
    'contentType': 'text/plain',
    'fileSize': 3 * 1024 * 1024,
    'fileCategory': 'EMERGENCY_CONTACT',
  },
  {
    'id': 4,
    'originalFilename': 'rx.pdf',
    'filename': 'rx.pdf',
    'contentType': 'application/pdf',
    'fileSize': 100,
    'fileCategory': 'PRESCRIPTION',
  },
];

class _Backend {
  bool deleteOk = true;
  final List<String> calls = [];

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        calls.add('${req.method} $path');
        if (req.method == 'DELETE') {
          return deleteOk
              ? http.Response('{}', 200)
              : http.Response('{"error":"nope"}', 500);
        }
        if (path.contains('/patient/')) {
          return http.Response(jsonEncode({'data': _files}), 200);
        }
        if (path.endsWith('/users/1/download')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        if (path.contains('/download')) {
          return http.Response('{"error":"missing"}', 404);
        }
        return http.Response('{}', 404);
      });
}

Widget _wrap({String role = 'CAREGIVER'}) =>
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(role: role, patientId: 7, caregiverId: 3)),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PatientFilesPage(patientId: 7, patientName: 'Jane Doe'),
      ),
    );

Future<void> _pump(WidgetTester tester, {String role = 'CAREGIVER'}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(role: role));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _clearSnack(WidgetTester tester) {
  ScaffoldMessenger.of(tester.element(find.byType(TabBar)))
      .removeCurrentSnackBar();
}

void main() {
  late AppLocalizations t;

  setUp(() {
    t = lookupAppLocalizations(const Locale('en'));
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
  });

  testWidgets('lists files and filters by category', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.text('visit_note.pdf'), findsOneWidget);
      expect(find.text('rash.png'), findsOneWidget);
      expect(find.text('Follow-up visit'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_prescripItem).last);
      await tester.pumpAndSettle();
      expect(find.text('rx.pdf'), findsOneWidget);
      expect(find.text('visit_note.pdf'), findsNothing);

      // Refresh reloads the list.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }, _Backend().client);
  });

  testWidgets('document preview downloads; image preview handles failure',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('visit_note.pdf'));
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_documentPreview), findsOneWidget);
      expect(find.textContaining('Follow-up visit'), findsWidgets);
      await tester.tap(find.text(t.ptfiles_downloadViewButton));
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDownloadSuccess), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      _clearSnack(tester);

      await tester.tap(find.text('rash.png'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(t.ptfiles_failedToLoadImage), findsOneWidget);
      // Header download button.
      await tester.tap(find.byIcon(Icons.download).last);
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDownloadFailed), findsOneWidget);
    }, _Backend().client);
  });

  testWidgets('non-previewable file downloads directly from the menu',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('contacts.txt'));
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDownloadFailed), findsOneWidget);
      _clearSnack(tester);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_previewButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_documentPreview), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_downloadButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDownloadSuccess), findsOneWidget);
    }, _Backend().client);
  });

  testWidgets('delete confirms, succeeds, then fails', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_deleteButton).last);
      await tester.pumpAndSettle();
      // Cancel first.
      await tester.tap(find.text(t.cancel));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_deleteButton).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, t.ptfiles_deleteButton));
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDeleteSuccess), findsOneWidget);
      _clearSnack(tester);
      await tester.pumpAndSettle();

      backend.deleteOk = false;
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_deleteButton).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, t.ptfiles_deleteButton));
      await tester.pumpAndSettle();
      expect(find.text(t.ptfiles_fileDeleteFailed), findsOneWidget);
    }, backend.client);
    expect(backend.calls.where((c) => c.startsWith('DELETE')), hasLength(2));
  });

  testWidgets('structured entry opens for supported categories',
      (tester) async {
    final calls = <String>[];
    StructuredEntryService.client = MockClient((req) async {
      calls.add(req.url.path);
      return calls.length == 1
          ? http.Response('{}', 404)
          : http.Response('{"error":"x"}', 500);
    });
    StructuredEntryService.authHeadersProvider = () async => {};
    addTearDown(() => StructuredEntryService.client = http.Client());

    await http.runWithClient(() async {
      await _pump(tester);
      final menu = find.byType(PopupMenuButton<String>).at(2);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_structEntry).last);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsWidgets);
      Navigator.of(tester.element(find.byType(Dialog).last)).pop();
      await tester.pumpAndSettle();

      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_structEntry).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed to load structured entry'),
          findsOneWidget);
    }, _Backend().client);
    expect(calls.first, contains('/3/structured-entry'));
  });

  testWidgets('checklist action and upload tab render', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, role: 'PATIENT');
      await tester.tap(find.byTooltip('Required documents checklist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();
    }, _Backend().client);
    expect(find.byType(PatientFilesPage), findsOneWidget);
  });
}
