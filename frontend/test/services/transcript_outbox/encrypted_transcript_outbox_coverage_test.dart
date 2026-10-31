import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/transcript_outbox/encrypted_transcript_outbox.dart';
import 'package:care_connect_app/services/transcript_outbox/pending_transcript_segment.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyStorage implements TranscriptKeyStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

PendingTranscriptSegment _segment(String id, String text) {
  final now = DateTime.utc(2026, 7, 19);
  return PendingTranscriptSegment(
    clientSegmentId: id,
    ownerUserId: 'user-1',
    callId: 'call-1',
    speakerLabel: 'PATIENT',
    text: text,
    startMs: 0,
    endMs: 1000,
    source: 'test',
    createdAt: now,
    nextAttemptAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _MemoryKeyStorage keys;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('transcript-outbox-cov-');
    EncryptedTranscriptOutbox.initializeHiveForTesting(directory.path);
  });

  setUp(() async {
    keys = _MemoryKeyStorage();
    await EncryptedTranscriptOutbox.purgeDefault(keyStorage: keys);
  });

  tearDownAll(() async {
    await EncryptedTranscriptOutbox.purgeDefault(keyStorage: keys);
    await directory.delete(recursive: true);
  });

  test('quota exception has a readable message', () {
    expect(
      const TranscriptOutboxQuotaExceeded().toString(),
      'The encrypted transcript outbox is full.',
    );
  });

  test('SecureTranscriptKeyStorage reads, writes and deletes', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = SecureTranscriptKeyStorage();
    await storage.write('k', 'v');
    expect(await storage.read('k'), 'v');
    await storage.delete('k');
    expect(await storage.read('k'), isNull);
  });

  test('invalid key length is rejected', () async {
    keys.values['careconnect_transcript_outbox_aes_key_v1'] =
        base64UrlEncode(List<int>.filled(8, 1));
    await expectLater(
      EncryptedTranscriptOutbox.open(ownerUserId: 'user-1', keyStorage: keys),
      throwsStateError,
    );
  });

  test('add, quota, update, remove, purge', () async {
    final box = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
      maxEntries: 1,
    );
    await box.add(_segment('a', 'one'));
    await box.add(_segment('a', 'dup ignored'));
    await expectLater(
      box.add(_segment('b', 'two')),
      throwsA(isA<TranscriptOutboxQuotaExceeded>()),
    );

    await box.update(_segment('a', 'updated'));
    await box.update(_segment('missing', 'nope'));
    expect((await box.all()).single.text, 'updated');

    await box.remove('a');
    expect(await box.all(), isEmpty);

    await box.purge();
    expect(keys.values, isEmpty);
  });

  test('open while box already open deletes ciphertext on owner change',
      () async {
    final first = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
    );
    await first.add(_segment('a', 'one'));
    // Reopen as different owner while the box is still open.
    final second = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-2',
      keyStorage: keys,
    );
    expect(await second.all(), isEmpty);
    await second.close();
  });

  test('MemoryTranscriptOutbox enforces quota and supports CRUD', () async {
    final mem = MemoryTranscriptOutbox(maxEntries: 1);
    await mem.add(_segment('a', 'one'));
    await expectLater(
      mem.add(_segment('b', 'two')),
      throwsA(isA<TranscriptOutboxQuotaExceeded>()),
    );
    await mem.update(_segment('a', 'changed'));
    expect((await mem.all()).single.text, 'changed');
    await mem.remove('a');
    await mem.add(_segment('c', 'three'));
    await mem.purge();
    expect(await mem.all(), isEmpty);
    await mem.close();
  });
}
