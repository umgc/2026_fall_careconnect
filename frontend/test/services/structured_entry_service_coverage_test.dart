import 'dart:convert';

import 'package:care_connect_app/services/structured_entry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _entry(int id) => {
      'id': id,
      'fileId': 9,
      'documentType': 'TAX_FORM',
      'fields': {'name': 'Jane', 'year': 2024, 'blank': null},
    };

void main() {
  late http.Client originalClient;
  late Future<Map<String, String>> Function() originalHeaders;

  setUp(() {
    originalClient = StructuredEntryService.client;
    originalHeaders = StructuredEntryService.authHeadersProvider;
    StructuredEntryService.authHeadersProvider =
        () async => <String, String>{'Authorization': 'Bearer t'};
  });

  tearDown(() {
    StructuredEntryService.client = originalClient;
    StructuredEntryService.authHeadersProvider = originalHeaders;
  });

  test('getEntryForFile parses fields map, 404 → null, other errors throw',
      () async {
    StructuredEntryService.client = MockClient((req) async {
      if (req.url.path.contains('/1/')) {
        return http.Response(jsonEncode({'data': _entry(1)}), 200);
      }
      if (req.url.path.contains('/2/')) {
        return http.Response('{}', 404);
      }
      return http.Response(jsonEncode({'error': 'Server down'}), 500);
    });

    final dto = await StructuredEntryService.getEntryForFile(1);
    expect(dto!.fields['name'], 'Jane');
    expect(dto.fields['year'], '2024');
    expect(dto.fields['blank'], '');

    expect(await StructuredEntryService.getEntryForFile(2), isNull);
    await expectLater(
      StructuredEntryService.getEntryForFile(3),
      throwsA(isA<Exception>()),
    );
  });

  test('updateEntry succeeds and fails', () async {
    StructuredEntryService.client = MockClient((req) async {
      expect(req.method, 'PUT');
      if (req.url.path.endsWith('/5')) {
        return http.Response(jsonEncode({'data': _entry(5)}), 200);
      }
      return http.Response(jsonEncode({}), 400);
    });

    final dto = await StructuredEntryService.updateEntry(
      entryId: 5,
      documentType: 'TAX_FORM',
      fields: {'name': 'Jane'},
      patientId: 1,
    );
    expect(dto.id, 5);

    await expectLater(
      StructuredEntryService.updateEntry(
        entryId: 6,
        documentType: 'TAX_FORM',
        fields: {},
      ),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg',
          contains('Failed to update structured entry'))),
    );
  });

  test('listEntriesForPatient returns list, empty on error', () async {
    StructuredEntryService.client = MockClient((req) async {
      if (req.url.path.endsWith('/patient/1')) {
        return http.Response(
          jsonEncode({
            'data': [_entry(1), _entry(2)],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'error': 'nope'}), 403);
    });

    final list = await StructuredEntryService.listEntriesForPatient(1);
    expect(list, hasLength(2));
    expect(await StructuredEntryService.listEntriesForPatient(2), isEmpty);
  });

  test('createEntry error without message uses default text', () async {
    StructuredEntryService.client =
        MockClient((req) async => http.Response(jsonEncode({}), 422));
    await expectLater(
      StructuredEntryService.createEntry(
        fileId: 1,
        documentType: 'TAX_FORM',
        fields: {},
      ),
      throwsA(isA<Exception>()),
    );
  });
}
