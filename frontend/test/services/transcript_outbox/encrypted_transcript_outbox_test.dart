import 'dart:io';

import 'package:care_connect_app/services/transcript_outbox/encrypted_transcript_outbox.dart';
import 'package:care_connect_app/services/transcript_outbox/pending_transcript_segment.dart';
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
  late Directory directory;
  late _MemoryKeyStorage keys;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('transcript-outbox-');
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

  test('persists encrypted segments and reopens with the same key', () async {
    const phi = 'patient-secret-phrase';
    final first = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
    );
    await first.add(_segment('773ad6ae-f41a-47b0-a1b9-d15ae8e199ec', phi));
    await first.close();

    final bytes = <int>[];
    await for (final entity in directory.list()) {
      if (entity is File) bytes.addAll(await entity.readAsBytes());
    }
    expect(String.fromCharCodes(bytes), isNot(contains(phi)));

    final reopened = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
    );
    expect((await reopened.all()).single.text, phi);
    await reopened.close();
  });

  test('account change purges prior ciphertext and key', () async {
    final first = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
    );
    await first.add(_segment(
      '61ba5e36-a78d-49e2-b266-c065b9a424f4',
      'private words',
    ));
    await first.close();
    final oldKey = keys.values.values.firstWhere((value) => value.length > 20);

    final second = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-2',
      keyStorage: keys,
    );
    expect(await second.all(), isEmpty);
    expect(keys.values.values, isNot(contains(oldKey)));
    await second.close();
  });

  test('quota rejects overflow without dropping existing ciphertext', () async {
    final outbox = await EncryptedTranscriptOutbox.open(
      ownerUserId: 'user-1',
      keyStorage: keys,
      maxEntries: 1,
    );
    await outbox.add(
      _segment('23a68ca2-f4eb-481a-a14f-1a153941b4d2', 'first'),
    );

    await expectLater(
      outbox.add(
        _segment('7e825a0b-2692-4e6e-bd4e-198f30604edf', 'second'),
      ),
      throwsA(isA<TranscriptOutboxQuotaExceeded>()),
    );
    expect((await outbox.all()).single.text, 'first');
    await outbox.close();
  });
}
