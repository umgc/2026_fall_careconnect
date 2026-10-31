// Coverage tests for ImportIcsButton
// (lib/features/tasks/presentation/widgets/import_ics_button.dart): importing
// an .ics file with UNTIL/BYDAY recurrence against a mocked task API,
// counting created, offline-queued and failed events in the summary
// snackbar, and the callback after the import.

import 'dart:convert';

import 'package:care_connect_app/features/tasks/presentation/widgets/import_ics_button.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FakePicker {
  _FakePicker(this.result);
  final FilePickerResult? result;

  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async =>
      result;
}

const _ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Lab visit
DESCRIPTION:Blood draw
DTSTART:20261102T090000
DTEND:20261102T093000
RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261130;BYDAY=MO,WE,XX;BAD
END:VEVENT
BEGIN:VEVENT
SUMMARY:Exercise walk
DTSTART:20261103
END:VEVENT
BEGIN:VEVENT
SUMMARY:Workout
DTSTART:notadate
END:VEVENT
END:VCALENDAR
''';

_FakePicker _picker(String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return _FakePicker(FilePickerResult(
      [PlatformFile(name: 'cal.ics', bytes: bytes, size: bytes.length)]));
}

Future<void> _import(WidgetTester tester, _FakePicker picker,
    {VoidCallback? onDone}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ImportIcsButton(
        patientNames: const {3: 'Pat Doe'},
        onTasksImported: onDone,
        filePicker: picker,
      ),
    ),
  ));
  await tester.tap(find.text('Import ICS'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pat Doe').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose File'));
  await tester.pumpAndSettle();
}

void main() {
  late List<http.Request> requests;

  setUp(() {
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    ApiService.debugResetHttpClient();
  });

  testWidgets('summarises created, queued and failed events',
      (tester) async {
    ApiService.debugSetHttpClient(MockClient((r) async {
      requests.add(r);
      final name = (jsonDecode(r.body) as Map)['name'];
      if (name == 'Lab visit') {
        return http.Response('{}', 201, headers: {'x-offline-queued': 'true'});
      }
      if (name == 'Workout') return http.Response('{}', 500);
      return http.Response('{}', 200);
    }));
    var done = 0;
    await _import(tester, _picker(_ics), onDone: () => done++);

    expect(requests, hasLength(3));
    expect(requests.first.url.path, endsWith('/patient/3'));
    final first = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(first['name'], 'Lab visit');
    expect(find.text('Imported 2 tasks (1 queued for sync)'), findsOneWidget);
    expect(done, 1);
  });

  testWidgets('all-queued imports announce the offline sync',
      (tester) async {
    ApiService.debugSetHttpClient(MockClient((r) async =>
        http.Response('{}', 200, headers: {'x-offline-queued': 'true'})));
    await _import(tester, _picker('''
BEGIN:VEVENT
SUMMARY:Medication
DTSTART:20261103T080000
END:VEVENT
'''));
    expect(find.text('Imported tasks queued for sync when internet is restored'),
        findsOneWidget);
  });

  testWidgets('an API exception is skipped and counted as not imported',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((r) async => throw http.ClientException('offline')));
    await _import(tester, _picker('''
BEGIN:VEVENT
SUMMARY:Checkup
DTSTART:20261103T080000
END:VEVENT
'''));
    expect(find.text('Imported 0 tasks'), findsOneWidget);
  });
}
