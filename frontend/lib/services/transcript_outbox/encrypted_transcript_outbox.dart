import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'pending_transcript_segment.dart';

abstract interface class TranscriptOutbox {
  Future<void> add(PendingTranscriptSegment segment);
  Future<void> update(PendingTranscriptSegment segment);
  Future<void> remove(String clientSegmentId);
  Future<List<PendingTranscriptSegment>> all();
  Future<void> purge();
  Future<void> close();
}

class TranscriptOutboxQuotaExceeded implements Exception {
  const TranscriptOutboxQuotaExceeded();

  @override
  String toString() => 'The encrypted transcript outbox is full.';
}

abstract interface class TranscriptKeyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTranscriptKeyStorage implements TranscriptKeyStorage {
  const SecureTranscriptKeyStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      webOptions: WebOptions.defaultOptions,
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class EncryptedTranscriptOutbox implements TranscriptOutbox {
  EncryptedTranscriptOutbox._(
    this._box,
    this._keyStorage, {
    required this.maxEntries,
    required this.maxEncryptedBytes,
  });

  static const String boxName = 'careconnect_transcript_outbox_v1';
  static const String _keyName = 'careconnect_transcript_outbox_aes_key_v1';
  static const String _ownerName = 'careconnect_transcript_outbox_owner_v1';
  static bool _hiveInitialized = false;

  final Box<dynamic> _box;
  final TranscriptKeyStorage _keyStorage;
  final int maxEntries;
  final int maxEncryptedBytes;

  static Future<EncryptedTranscriptOutbox> open({
    required String ownerUserId,
    TranscriptKeyStorage keyStorage = const SecureTranscriptKeyStorage(),
    int maxEntries = 500,
    int maxEncryptedBytes = 4 * 1024 * 1024,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Encrypted transcript outbox persistence is not supported on web; '
        'PHI segments require a native secure keystore.',
      );
    }
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(ownerUserId, 'ownerUserId');
    }
    await _initializeHive();

    final previousOwner = await keyStorage.read(_ownerName);
    if (previousOwner != null && previousOwner != owner) {
      await _deleteCiphertext();
      await keyStorage.delete(_keyName);
      await keyStorage.delete(_ownerName);
    }

    var encodedKey = await keyStorage.read(_keyName);
    if (encodedKey == null) {
      await _deleteCiphertext();
      encodedKey = base64UrlEncode(Hive.generateSecureKey());
      await keyStorage.write(_keyName, encodedKey);
    }

    final key = base64Url.decode(base64Url.normalize(encodedKey));
    if (key.length != 32) {
      await _deleteCiphertext();
      await keyStorage.delete(_keyName);
      throw StateError('Transcript outbox encryption key is invalid.');
    }

    final box = await Hive.openBox<dynamic>(
      boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    await keyStorage.write(_ownerName, owner);
    return EncryptedTranscriptOutbox._(
      box,
      keyStorage,
      maxEntries: maxEntries,
      maxEncryptedBytes: maxEncryptedBytes,
    );
  }

  static Future<void> _initializeHive() async {
    if (_hiveInitialized) return;
    await Hive.initFlutter();
    _hiveInitialized = true;
  }

  @visibleForTesting
  static void initializeHiveForTesting(String path) {
    Hive.init(path);
    _hiveInitialized = true;
  }

  static Future<void> _deleteCiphertext() async {
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<dynamic>(boxName).deleteFromDisk();
      return;
    }
    if (await Hive.boxExists(boxName)) {
      await Hive.deleteBoxFromDisk(boxName);
    }
  }

  static Future<void> purgeDefault({
    TranscriptKeyStorage keyStorage = const SecureTranscriptKeyStorage(),
  }) async {
    await _initializeHive();
    await _deleteCiphertext();
    await keyStorage.delete(_keyName);
    await keyStorage.delete(_ownerName);
  }

  @override
  Future<void> add(PendingTranscriptSegment segment) async {
    if (_box.containsKey(segment.clientSegmentId)) {
      return;
    }
    final encoded = jsonEncode(segment.toJson());
    var usedBytes = 0;
    for (final value in _box.values) {
      usedBytes += utf8.encode(jsonEncode(value)).length;
    }
    if (_box.length >= maxEntries ||
        usedBytes + utf8.encode(encoded).length > maxEncryptedBytes) {
      throw const TranscriptOutboxQuotaExceeded();
    }
    await _box.put(segment.clientSegmentId, segment.toJson());
    await _box.flush();
  }

  @override
  Future<void> update(PendingTranscriptSegment segment) async {
    if (!_box.containsKey(segment.clientSegmentId)) return;
    await _box.put(segment.clientSegmentId, segment.toJson());
    await _box.flush();
  }

  @override
  Future<void> remove(String clientSegmentId) async {
    await _box.delete(clientSegmentId);
    await _box.flush();
  }

  @override
  Future<List<PendingTranscriptSegment>> all() async {
    return _box.values
        .map((value) => PendingTranscriptSegment.fromJson(
              Map<dynamic, dynamic>.from(value as Map),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> purge() async {
    await _box.deleteFromDisk();
    await _keyStorage.delete(_keyName);
    await _keyStorage.delete(_ownerName);
  }

  @override
  Future<void> close() => _box.close();
}

class MemoryTranscriptOutbox implements TranscriptOutbox {
  MemoryTranscriptOutbox({this.maxEntries = 500});

  final int maxEntries;
  final Map<String, PendingTranscriptSegment> _segments =
      <String, PendingTranscriptSegment>{};

  @override
  Future<void> add(PendingTranscriptSegment segment) async {
    if (!_segments.containsKey(segment.clientSegmentId) &&
        _segments.length >= maxEntries) {
      throw const TranscriptOutboxQuotaExceeded();
    }
    _segments.putIfAbsent(segment.clientSegmentId, () => segment);
  }

  @override
  Future<List<PendingTranscriptSegment>> all() async =>
      _segments.values.toList(growable: false);

  @override
  Future<void> close() async {}

  @override
  Future<void> purge() async => _segments.clear();

  @override
  Future<void> remove(String clientSegmentId) async =>
      _segments.remove(clientSegmentId);

  @override
  Future<void> update(PendingTranscriptSegment segment) async {
    if (_segments.containsKey(segment.clientSegmentId)) {
      _segments[segment.clientSegmentId] = segment;
    }
  }
}
