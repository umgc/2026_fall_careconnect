// Coverage tests for HomeCareDocumentApi: fetchDocumentTypes (backend +
// local fallback) and extract (multipart upload + manual fallbacks).

import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:care_connect_app/features/homecare_documents/services/home_care_document_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _withClient<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

const _type = HomeCareDocumentTypeInfo(
  type: 'CARE_PLAN',
  displayName: 'Care Plan',
  fields: [HomeCareFieldSpec(key: 'name', label: 'Name')],
);

// Minimal PNG signature so mime lookup resolves to image/png.
final _pngBytes = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'hc-jwt',
      'token_expiry': '$expiry',
    });
  });

  group('fetchDocumentTypes', () {
    test('returns backend types when the list is non-empty', () async {
      late http.Request seen;
      final types = await _withClient(
        HomeCareDocumentApi.fetchDocumentTypes,
        (req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'type': 'INTAKE',
                'displayName': 'Intake',
                'fields': [
                  {'key': 'a', 'label': 'A'},
                ],
              },
            ]),
            200,
          );
        },
      );
      expect(types.single.type, 'INTAKE');
      expect(types.single.fields.single.key, 'a');
      expect(seen.url.path, endsWith('/types'));
      expect(seen.headers['Authorization'], 'Bearer hc-jwt');
    });

    test('falls back to local types for an empty list', () async {
      final types = await _withClient(
        HomeCareDocumentApi.fetchDocumentTypes,
        (_) async => http.Response('[]', 200),
      );
      expect(types, same(defaultHomeCareDocumentTypes));
    });

    test('falls back to local types for a non-list body', () async {
      final types = await _withClient(
        HomeCareDocumentApi.fetchDocumentTypes,
        (_) async => http.Response('{"types":[]}', 200),
      );
      expect(types, same(defaultHomeCareDocumentTypes));
    });

    test('falls back to local types on non-200', () async {
      final types = await _withClient(
        HomeCareDocumentApi.fetchDocumentTypes,
        (_) async => http.Response('', 503),
      );
      expect(types, same(defaultHomeCareDocumentTypes));
    });

    test('falls back to local types when the request throws', () async {
      final types = await _withClient(
        HomeCareDocumentApi.fetchDocumentTypes,
        (_) async => throw http.ClientException('offline'),
      );
      expect(types, same(defaultHomeCareDocumentTypes));
    });
  });

  group('extract', () {
    test('uploads files as multipart and parses the extraction', () async {
      late http.Request seen;
      final result = await _withClient(
        () => HomeCareDocumentApi.extract(
          documentType: _type,
          files: [
            PickedHomeCareFile(bytes: _pngBytes, name: 'scan.png'),
            PickedHomeCareFile(
              bytes: Uint8List.fromList([1, 2, 3]),
              name: 'blob.unknownext',
            ),
          ],
        ),
        (req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'documentType': 'CARE_PLAN',
              'documentTypeDisplayName': 'Care Plan',
              'status': 'PREFILLED',
              'fields': [
                {'key': 'name', 'label': 'Name', 'value': 'Ann'},
              ],
            }),
            200,
          );
        },
      );
      expect(result.status, 'PREFILLED');
      expect(result.fields.single.value, 'Ann');
      expect(seen.method, 'POST');
      expect(seen.url.path, endsWith('/extract'));
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      expect(seen.headers['Authorization'], 'Bearer hc-jwt');
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('CARE_PLAN'));
      expect(body, contains('filename="scan.png"'));
      expect(body, contains('image/png'));
      expect(body, contains('application/octet-stream'));
    });

    test('returns manual fallback when response lacks fields', () async {
      final result = await _withClient(
        () =>
            HomeCareDocumentApi.extract(documentType: _type, files: const []),
        (_) async => http.Response('{"status":"x"}', 200),
      );
      expect(result.status, HomeCareExtractionStatus.manualEntryRequired);
      expect(result.message, contains('unavailable'));
      expect(result.documentType, 'CARE_PLAN');
    });

    test('returns manual fallback on non-200', () async {
      final result = await _withClient(
        () =>
            HomeCareDocumentApi.extract(documentType: _type, files: const []),
        (_) async => http.Response('fail', 500),
      );
      expect(result.message, contains('unavailable'));
    });

    test('returns manual fallback when the upload throws', () async {
      final result = await _withClient(
        () =>
            HomeCareDocumentApi.extract(documentType: _type, files: const []),
        (_) async => throw http.ClientException('down'),
      );
      expect(result.status, HomeCareExtractionStatus.manualEntryRequired);
      expect(result.message, contains('failed'));
    });
  });
}
