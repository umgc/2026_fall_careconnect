// Gap coverage for ImportIcsButton: drives the whole import flow (dialog,
// patient dropdown, picker, ICS parsing, task creation) and checks the task
// requests sent to the backend and the result snackbars. HTTP goes through
// ApiService.debugSetHttpClient with a MockClient; the file picker is a fake.
import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/features/tasks/presentation/widgets/import_ics_button.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePicker {
  _FakePicker(this.result);
  final FilePickerResult? result;
  int calls = 0;
  List<String>? lastExtensions;

  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    calls++;
    lastExtensions = allowedExtensions;
    return result;
  }
}

FilePickerResult _icsResult(String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return FilePickerResult([
    PlatformFile(name: 'cal.ics', bytes: bytes, size: bytes.length),
  ]);
}

String _event(String lines) => 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
    '${lines.trim().split('\n').map((l) => l.trim()).join('\r\n')}\r\n'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  var imported = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    imported = 0;
    respond = (_) => http.Response('{}', 201);
    ApiService.debugSetHttpClient(
      MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
  });

  Future<_FakePicker> runImport(
    WidgetTester tester,
    FilePickerResult? result, {
    bool selectPatient = true,
  }) async {
    final picker = _FakePicker(result);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ImportIcsButton(
            patientNames: const {1: 'Alice', 2: 'Bob'},
            filePicker: picker,
            onTasksImported: () => imported++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import ICS'));
    await tester.pumpAndSettle();
    if (selectPatient) {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Choose File'));
    await tester.pumpAndSettle();
    return picker;
  }

  testWidgets('posts one task per VEVENT for the chosen patient',
      (tester) async {
    final picker = await runImport(
      tester,
      _icsResult(
        '${_event('''
SUMMARY:Cardiology Appointment
DESCRIPTION:Bring the list
DTSTART:20260105T090000Z
DTEND:20260105T100000Z
''')}${_event('''
SUMMARY:Evening walk
DTSTART:20260106
''')}',
      ),
    );

    expect(picker.lastExtensions, ['ics']);
    expect(requests, hasLength(2));
    expect(requests.every((r) => r.method == 'POST'), isTrue);
    expect(requests.every((r) => r.url.path.endsWith('/patient/2')), isTrue);

    final first = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(first['name'], 'Cardiology Appointment');
    expect(first['description'], 'Bring the list');
    expect(first['taskType'], 'appointment');
    expect(first['patientId'], 2);
    expect(first['timeOfDay'], '10:00');
    expect(first['date'], startsWith('2026-01-05T09:00'));

    final second = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(second['name'], 'Evening walk');
    expect(second['taskType'], 'imported');
    expect(second['date'], startsWith('2026-01-06'));

    expect(find.text('Imported 2 tasks'), findsOneWidget);
    expect(imported, 1);
  });

  testWidgets('uses singular wording for a single task', (tester) async {
    await runImport(
        tester, _icsResult(_event('SUMMARY:Labs\nDTSTART:20260105')));

    expect(find.text('Imported 1 task'), findsOneWidget);
    expect(jsonDecode(requests.single.body)['taskType'], 'lab');
  });

  testWidgets('sends recurrence details from RRULE', (tester) async {
    await runImport(
      tester,
      _icsResult(
        _event('''
SUMMARY:Take medication
DTSTART:20260105T080000
RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=6;BYDAY=MO,WE
'''),
      ),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['taskType'], 'medication');
    expect(body['frequency'].toString().toLowerCase(), 'weekly');
    expect(body['interval'], 2);
    expect(body['count'], 6);
    expect(body['daysOfWeek'], [false, true, false, true, false, false, false]);
  });

  testWidgets('derives a count from UNTIL when COUNT is missing',
      (tester) async {
    await runImport(
      tester,
      _icsResult(
        _event('''
SUMMARY:Exercise
DTSTART:20260105T080000
RRULE:FREQ=DAILY;UNTIL=20260109T080000
'''),
      ),
    );

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['taskType'], 'exercise');
    expect(body['count'], isA<int>());
    expect(body['count'], greaterThanOrEqualTo(4));
  });

  testWidgets('counts only successful creations and logs failures',
      (tester) async {
    var n = 0;
    respond = (_) => (n++ == 0)
        ? http.Response('{}', 200)
        : http.Response('{"error":"bad"}', 500);

    await runImport(
      tester,
      _icsResult(
        '${_event('SUMMARY:A\nDTSTART:20260105')}'
        '${_event('SUMMARY:B\nDTSTART:20260106')}',
      ),
    );

    expect(requests, hasLength(2));
    expect(find.text('Imported 1 task'), findsOneWidget);
  });

  testWidgets('keeps going when a request throws', (tester) async {
    var n = 0;
    ApiService.debugSetHttpClient(
      MockClient((request) async {
        requests.add(request);
        if (n++ == 0) throw http.ClientException('offline');
        return http.Response('{}', 201);
      }),
    );

    await runImport(
      tester,
      _icsResult(
        '${_event('SUMMARY:A\nDTSTART:20260105')}'
        '${_event('SUMMARY:B\nDTSTART:20260106')}',
      ),
    );

    expect(requests, hasLength(2));
    expect(find.text('Imported 1 task'), findsOneWidget);
    expect(imported, 1);
  });

  testWidgets('says tasks are queued when everything was queued offline',
      (tester) async {
    respond = (_) => http.Response('{}', 202, headers: {
          'x-offline-queued': 'true',
        });

    await runImport(tester, _icsResult(_event('SUMMARY:A\nDTSTART:20260105')));

    expect(
      find.text('Imported tasks queued for sync when internet is restored'),
      findsOneWidget,
    );
  });

  testWidgets('reports a mix of sent and queued tasks', (tester) async {
    var n = 0;
    respond = (_) => (n++ == 0)
        ? http.Response('{}', 201)
        : http.Response('{}', 202, headers: {'x-offline-queued': 'true'});

    await runImport(
      tester,
      _icsResult(
        '${_event('SUMMARY:A\nDTSTART:20260105')}'
        '${_event('SUMMARY:B\nDTSTART:20260106')}',
      ),
    );

    expect(find.text('Imported 2 tasks (1 queued for sync)'), findsOneWidget);
  });

  testWidgets('does nothing when the picker is cancelled', (tester) async {
    final picker = await runImport(tester, null);

    expect(picker.calls, 1);
    expect(requests, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(imported, 0);
  });

  testWidgets('does nothing when the chosen file has no bytes', (tester) async {
    await runImport(
      tester,
      FilePickerResult([PlatformFile(name: 'cal.ics', size: 0)]),
    );

    expect(requests, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('does not open the picker until a patient is chosen',
      (tester) async {
    final picker = await runImport(
      tester,
      _icsResult(_event('SUMMARY:A\nDTSTART:20260105')),
      selectPatient: false,
    );

    expect(picker.calls, 0);
    expect(requests, isEmpty);
    expect(
      find.text('Please select a patient before importing.'),
      findsOneWidget,
    );
  });

  testWidgets('tolerates malformed lines and bad dates', (tester) async {
    await runImport(
      tester,
      _icsResult(
        'BEGIN:VCALENDAR\nGARBAGE\nBEGIN:VEVENT\nNOCOLON\n'
        'SUMMARY:Odd: title\nDTSTART:bogus\nRRULE:FREQ\nEND:VEVENT\n'
        'END:VCALENDAR',
      ),
    );

    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['name'], 'Odd: title');
  });

  testWidgets('reports zero tasks for a file with no events', (tester) async {
    await runImport(tester, _icsResult('BEGIN:VCALENDAR\nEND:VCALENDAR'));
    expect(requests, isEmpty);
    expect(find.text('Imported 0 tasks'), findsOneWidget);
  });
}
