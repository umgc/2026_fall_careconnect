import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles encryption key lifecycle for the local SQLCipher database.
///
/// Keys are stored in platform secure storage and reused across app launches.
class DbEncryptionService {
  DbEncryptionService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(webOptions: WebOptions.defaultOptions);

  static const String _encryptionKeyStorageKey = 'careconnect_db_key_v1';
  final FlutterSecureStorage _storage;

  /// Returns an existing encryption key or creates and stores a new one.
  Future<String> getOrCreateEncryptionKey() async {
    final existing = await _storage.read(key: _encryptionKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = base64UrlEncode(bytes);
    await _storage.write(key: _encryptionKeyStorageKey, value: generated);
    return generated;
  }

  /// Returns true when an encryption key has already been stored.
  Future<bool> hasEncryptionKey() async {
    final existing = await _storage.read(key: _encryptionKeyStorageKey);
    return existing != null && existing.isNotEmpty;
  }

  /// Escapes single quotes for safe use in PRAGMA statements.
  String escapeForPragma(String rawKey) {
    return rawKey.replaceAll("'", "''");
  }

  /// Deletes the stored encryption key.
  ///
  /// Useful for factory-reset flows when the encrypted database is unreadable
  /// and needs to be recreated from scratch.
  Future<void> deleteKey() async {
    await _storage.delete(key: _encryptionKeyStorageKey);
  }
}
