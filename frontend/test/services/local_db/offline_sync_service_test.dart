import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/services/local_db/app_database.dart';
import 'package:care_connect_app/services/local_db/offline_sync_row.dart';
import 'package:care_connect_app/services/local_db/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../test_support/local_db_test_bindings.dart';

void main() {
  group('offline_sync_service.dart', () {
    late OfflineSyncService service;

    setUpAll(() async {
      await LocalDbTestBindings.install();
      service = OfflineSyncService.instance();
      await service.initialize();
    });

    setUp(() async {
      await _clearQueue(service);
    });

    tearDownAll(LocalDbTestBindings.uninstall);

    test('identifies queueable HTTP methods', () {
      expect(service.isQueueableMethod('POST'), isTrue);
      expect(service.isQueueableMethod('put'), isTrue);
      expect(service.isQueueableMethod('PATCH'), isTrue);
      expect(service.isQueueableMethod('DELETE'), isTrue);
      expect(service.isQueueableMethod('GET'), isFalse);
    });

    test('detects queue-worthy network errors', () {
      expect(service.shouldQueueForError(TimeoutException('timeout')), isTrue);
      expect(
        service.shouldQueueForError(
          http.ClientException('connection refused'),
        ),
        isTrue,
      );
      expect(service.shouldQueueForError(Exception('bad request')), isFalse);
      expect(
        service.shouldQueueForError(Exception('SocketException: failed host lookup')),
        isTrue,
      );
    });

    test('buildQueuedStreamedResponse returns expected queued payload', () async {
      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks'),
      );

      final streamed = service.buildQueuedStreamedResponse(
        request,
        queuedId: 'queued-123',
      );
      final response = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, equals(200));
      expect(response.headers['x-offline-queued'], equals('true'));
      expect(response.headers['x-offline-request-id'], equals('queued-123'));
      expect(decoded['queued'], isTrue);
      expect(decoded['requestId'], equals('queued-123'));
    });

    test('enqueueRequest deduplicates equivalent payloads', () async {
      final first = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/patient/1/mood'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"score":8,"label":"Good"}',
      );

      final second = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/patient/1/mood'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"score":8,"label":"Good"}',
      );

      expect(first, equals(second));
      expect(await service.getPendingCount(), equals(1));
    });

    test('enqueueRequest fingerprint ignores authorization header changes', () async {
      final first = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token-a',
        },
        body: '{"title":"Medication"}',
      );

      final second = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token-b',
        },
        body: '{"title":"Medication"}',
      );

      expect(first, equals(second));
      expect(await service.getPendingCount(), equals(1));
    });

    test('pending queue display is human-readable and does not expose endpoint info', () async {
      final moodId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/patient/1/mood'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"score":8,"label":"Good"}',
      );
      final taskId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body:
            '{"title":"Blood Pressure Check","note":"Use home cuff","taskDate":"2026-03-12","time":"09:30"}',
      );
      final genericId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/custom'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"patientName":"Mary Johnson","token":"secret-value"}',
      );

      final queue = await service.getPendingQueue(limit: 20);
      final mood = queue.firstWhere((item) => item.id == moodId);
      final task = queue.firstWhere((item) => item.id == taskId);
      final generic = queue.firstWhere((item) => item.id == genericId);

      expect(mood.displayTitle, equals('Mood Entry'));
      expect(mood.displayDetails.join(' '), contains('Mood rating'));

      expect(task.displayTitle, equals('Task'));
      expect(task.displayDetails.join(' '), contains('Title: Blood Pressure Check'));

      final genericDetails = generic.displayDetails.join(' ');
      expect(generic.displayTitle, equals('Queued Update'));
      expect(genericDetails, contains('Patient Name: Mary Johnson'));
      expect(genericDetails.toLowerCase(), isNot(contains('endpoint')));
      expect(genericDetails.toLowerCase(), isNot(contains('secret-value')));
      expect(genericDetails.toLowerCase(), isNot(contains('token')));
    });

    test('pending queue generic display limits fields and removes sensitive values', () async {
      final queuedId = await service.enqueueRequest(
        method: 'PATCH',
        uri: Uri.parse('https://example.org/v1/api/custom'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body:
            '{"fieldA":"a","fieldB":"b","fieldC":"c","fieldD":"d","fieldE":"e","fieldF":"f","password":"do-not-show","authorization":"do-not-show"}',
      );

      final queue = await service.getPendingQueue(limit: 10);
      final item = queue.firstWhere((entry) => entry.id == queuedId);

      expect(item.displayTitle, equals('Queued Update'));
      expect(item.displayDetails.length, lessThanOrEqualTo(5));
      final flattened = item.displayDetails.join(' ').toLowerCase();
      expect(flattened, isNot(contains('password')));
      expect(flattened, isNot(contains('authorization')));
      expect(flattened, isNot(contains('do-not-show')));
    });

    test('user case: queues mixed offline writes in order and supports pre-sync delete', () async {
      final moodId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/patient/1/mood'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"score":7,"label":"Okay"}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final taskId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body:
            '{"title":"Morning meds","note":"With food","taskDate":"2026-03-12","time":"08:00"}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final profileId = await service.enqueueRequest(
        method: 'PATCH',
        uri: Uri.parse('https://example.org/v1/api/profile'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"nickname":"MJ"}',
      );

      final queued = await service.getPendingQueue(limit: 10);
      expect(
        queued.map((item) => item.id).toList(),
        equals(<String>[moodId, taskId, profileId]),
      );

      final deleted = await service.deleteQueuedRequestById(taskId);
      expect(deleted, isTrue);

      final afterDelete = await service.getPendingQueue(limit: 10);
      expect(afterDelete.map((item) => item.id), isNot(contains(taskId)));
      expect(afterDelete.length, equals(2));
    });

    test('user case: task payload nested under task field is human-readable', () async {
      final queuedId = await service.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body:
            '{"task":"{\\"title\\":\\"Evening Walk\\",\\"note\\":\\"15 minutes\\",\\"taskDate\\":\\"2026-03-12\\",\\"time\\":\\"18:30\\"}"}',
      );

      final queue = await service.getPendingQueue(limit: 10);
      final item = queue.firstWhere((entry) => entry.id == queuedId);
      final details = item.displayDetails.join(' ');

      expect(item.displayTitle, equals('Task'));
      expect(details, contains('Title: Evening Walk'));
      expect(details, contains('Note: 15 minutes'));
      expect(details, contains('Task date: 2026-03-12'));
      expect(details, contains('Task time: 18:30'));
    });

    test('syncPendingQueue reports zero attempts when queue is empty', () async {
      final summary = await service.syncPendingQueue(limit: 50);
      expect(summary.attempted, equals(0));
      expect(summary.succeeded, equals(0));
      expect(summary.failed, equals(0));
    });

    test('deleteQueuedRequestById returns false for unknown id', () async {
      expect(await service.deleteQueuedRequestById('does-not-exist'), isFalse);
    });

    test('syncQueuedRequestById returns true for unknown id', () async {
      expect(await service.syncQueuedRequestById('missing-id'), isTrue);
    });

    test('user case: malformed queued URL is marked failed during single-item sync', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-item',
        method: 'POST',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"invalid"}',
        createdAtIso: '2026-03-12T15:00:00.000Z',
        fingerprint: 'fp-bad-url-item',
      );
      await db.closeDb();

      final ok = await service.syncQueuedRequestById('bad-url-item');
      expect(ok, isFalse);

      final verifyDb = AppDatabase();
      final row = await verifyDb.getOfflineSyncById('bad-url-item');
      expect(row, isNotNull);
      expect(row!.status, equals('failed'));
      expect(row.retryCount, equals(1));
      expect(row.lastError, contains('Invalid queued URL'));
      await verifyDb.deleteOfflineSyncById('bad-url-item');
      await verifyDb.closeDb();
    });

    test('failed replay remains one failed row instead of being re-enqueued',
        () async {
      // Arrange
      final isolatedService = OfflineSyncService.forTesting(
        replayClient: _ThrowingClient(TimeoutException('offline')),
      );
      await isolatedService.initialize();
      addTearDown(() async {
        await _clearQueue(isolatedService);
        await isolatedService.close();
      });
      final queuedId = await isolatedService.enqueueRequest(
        method: 'POST',
        uri: Uri.parse('https://example.org/v1/api/tasks/patient/1'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"title":"Replay once"}',
      );

      // Act
      final synced = await isolatedService.syncQueuedRequestById(queuedId);
      final queue = await isolatedService.getPendingQueue(limit: 10);

      // Assert
      expect(synced, isFalse);
      expect(queue, hasLength(1));
      expect(queue.single.id, queuedId);
      expect(queue.single.status, OfflineSyncStatus.failed);
      expect(queue.single.retryCount, 1);
    });

    test('user case: syncPendingQueue summary counts deterministic malformed rows as failed', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-1',
        method: 'PUT',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"one"}',
        createdAtIso: '2026-03-12T15:01:00.000Z',
        fingerprint: 'fp-bad-url-1',
      );
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-2',
        method: 'PATCH',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"two"}',
        createdAtIso: '2026-03-12T15:02:00.000Z',
        fingerprint: 'fp-bad-url-2',
      );
      await db.closeDb();

      final summary = await service.syncPendingQueue(limit: 10);
      expect(summary.attempted, equals(2));
      expect(summary.succeeded, equals(0));
      expect(summary.failed, equals(2));

      final verifyDb = AppDatabase();
      final row1 = await verifyDb.getOfflineSyncById('bad-url-1');
      final row2 = await verifyDb.getOfflineSyncById('bad-url-2');
      expect(row1?.status, equals('failed'));
      expect(row2?.status, equals('failed'));
      await verifyDb.deleteOfflineSyncById('bad-url-1');
      await verifyDb.deleteOfflineSyncById('bad-url-2');
      await verifyDb.closeDb();
    });

    test('OfflineQueueHttpClient queues offline write requests', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      )..body = '{"title":"Queued"}';

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      expect(response.statusCode, equals(200));
      expect(response.headers['x-offline-queued'], equals('true'));
      expect(await service.getPendingCount(), equals(1));
    });

    test('OfflineQueueHttpClient does not queue GET requests', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.Request(
        'GET',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      );

      expect(
        () => client.send(request),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.getPendingCount(), equals(0));
    });

    test('OfflineQueueHttpClient does not queue replay-flagged requests', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      )
        ..headers[OfflineSyncService.replayHeader] = 'true'
        ..body = '{"title":"Replay"}';

      expect(
        () => client.send(request),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.getPendingCount(), equals(0));
    });

    test('OfflineQueueHttpClient does not queue auth endpoint writes', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/auth/login'),
      )..body = '{"email":"patient@careconnect.com"}';

      expect(
        () => client.send(request),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.getPendingCount(), equals(0));
    });

    test('OfflineQueueHttpClient respects canQueueWrites=false', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => false,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      )..body = '{"title":"Should fail"}';

      expect(
        () => client.send(request),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.getPendingCount(), equals(0));
    });

    test('OfflineQueueHttpClient does not queue multipart requests', () async {
      final client = OfflineQueueHttpClient(
        inner: _ThrowingClient(TimeoutException('offline')),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      );
      request.fields['title'] = 'Multipart task';

      expect(
        () => client.send(request),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.getPendingCount(), equals(0));
    });

    test('OfflineQueueHttpClient passes through successful responses', () async {
      final client = OfflineQueueHttpClient(
        inner: _StaticClient(statusCode: 201, body: '{"created":true}'),
        offlineSyncService: service,
        canQueueWrites: () => true,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.org/v1/api/tasks/patient/1'),
      )..body = '{"title":"New"}';

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      expect(response.statusCode, equals(201));
      expect(response.headers.containsKey('x-offline-queued'), isFalse);
      expect(await service.getPendingCount(), equals(0));
    });
  });
}

Future<void> _clearQueue(OfflineSyncService service) async {
  final pending = await service.getPendingQueue(limit: 2000);
  for (final item in pending) {
    await service.deleteQueuedRequestById(item.id);
  }
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}

class _StaticClient extends http.BaseClient {
  _StaticClient({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      request: request,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}
