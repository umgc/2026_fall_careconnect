import 'dart:convert';

import 'package:care_connect_app/services/local_db/offline_sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/local_db_test_bindings.dart';

String _jwt(int exp) {
  final h = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final p =
      base64Url.encode(utf8.encode(jsonEncode({'sub': '1', 'exp': exp})));
  return '$h.$p.sig';
}

Future<void> _clear(OfflineSyncService service) async {
  for (final item in await service.getPendingQueue(limit: 2000)) {
    await service.deleteQueuedRequestById(item.id);
  }
}

void main() {
  late OfflineSyncService service;
  final sentAuth = <String?>[];

  setUpAll(() async {
    await LocalDbTestBindings.install();
    service = OfflineSyncService.forTesting(
      replayClient: MockClient((req) async {
        sentAuth.add(req.headers['Authorization']);
        if (req.url.path.contains('fail')) {
          return http.Response('nope', 500);
        }
        return http.Response('{}', 200);
      }),
    );
    await service.initialize();
  });

  setUp(() async => _clear(service));

  tearDownAll(() async {
    await _clear(service);
    await service.close();
    await LocalDbTestBindings.uninstall();
  });

  Future<List<String>> displayFor(String path, String? body) async {
    final id = await service.enqueueRequest(
      method: 'POST',
      uri: Uri.parse('https://example.org$path'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        OfflineSyncService.replayHeader: '1',
      },
      body: body,
    );
    final item =
        (await service.getPendingQueue()).firstWhere((e) => e.id == id);
    return [item.displayTitle, ...item.displayDetails];
  }

  test('mood-pain-log display formats timestamp variants', () async {
    final iso = await displayFor(
      '/v1/api/mood-pain-log',
      jsonEncode({'moodValue': 4, 'timestamp': '2026-03-01T10:15:00Z'}),
    );
    expect(iso.first, 'Mood Check-In');
    expect(iso[1], 'Mood rating: 4');

    final bad = await displayFor(
      '/v1/api/mood-pain-log/2',
      jsonEncode({'timestamp': 'not-a-date'}),
    );
    expect(bad, contains('Date: not-a-date'));
  });

  test('task display expands nested task JSON string', () async {
    final details = await displayFor(
      '/v1/api/tasks/1',
      jsonEncode({
        'task': jsonEncode({'name': 'Walk', 'notes': 'outside'}),
      }),
    );
    expect(details.first, 'Task');
    expect(details, contains('Title: Walk'));
    expect(details, contains('Note: outside'));

    final broken = await displayFor(
      '/v1/api/tasks/2',
      jsonEncode({'task': '{not json', 'title': 'Fallback'}),
    );
    expect(broken, contains('Title: Fallback'));
  });

  test('generic display summarises value types', () async {
    final details = await displayFor(
      '/v1/api/profile',
      jsonEncode({
        'enabled': true,
        'tags': ['a', 'b'],
        'single': ['x'],
        'emptyList': [],
        'meta': {'k': 'v'},
        'emptyMap': {},
      }),
    );
    expect(details.first, 'Queued Update');
    expect(details, contains('Enabled: true'));
    expect(details, contains('Tags: 2 items'));
    expect(details, contains('Single: 1 item'));
    expect(details, contains('Meta: 1 field'));
  });

  test('empty or non-map bodies fall back to waiting text', () async {
    expect(await displayFor('/v1/api/other', null),
        ['Queued Update', 'Waiting to sync']);
    expect(await displayFor('/v1/api/other2', '[1,2]'),
        ['Queued Update', 'Waiting to sync']);
    expect(await displayFor('/v1/api/other3', '{broken'),
        ['Queued Update', 'Waiting to sync']);
  });

  test('syncPendingQueue counts successes and failures with auth header',
      () async {
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    // Seed a token so replay attaches Authorization.
    await _seedToken(_jwt(exp), exp);

    await service.enqueueRequest(
      method: 'POST',
      uri: Uri.parse('https://example.org/v1/api/ok'),
      body: '{"a":1}',
    );
    await service.enqueueRequest(
      method: 'PUT',
      uri: Uri.parse('https://example.org/v1/api/fail'),
      body: '{"a":2}',
    );
    final summary = await service.syncPendingQueue(limit: 10);
    expect(summary.attempted, 2);
    expect(summary.succeeded, 1);
    expect(summary.failed, 1);
  });
}

Future<void> _seedToken(String jwt, int exp) async {
  // LocalDbTestBindings stores secure-storage writes in memory; use the
  // platform channel through AuthTokenManager-compatible keys.
  const storage = _SecureWriter();
  await storage.write('jwt_token', jwt);
  await storage.write('token_expiry', '$exp');
}

class _SecureWriter {
  const _SecureWriter();

  Future<void> write(String key, String value) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'plugins.it_nomads.com/flutter_secure_storage',
      codec.encodeMethodCall(
        MethodCall('write', <String, dynamic>{'key': key, 'value': value}),
      ),
      (_) {},
    );
  }
}
