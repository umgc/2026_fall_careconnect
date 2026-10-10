import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'db_encryption_service.dart';
import 'offline_sync_row.dart';

/// Encrypted local database used only for offline sync queue persistence.
class AppDatabase {
  AppDatabase({DbEncryptionService? encryptionService})
      : _encryptionService = encryptionService ?? DbEncryptionService();

  final DbEncryptionService _encryptionService;
  sqlite.Database? _db;

  /// Maximum replay attempts before a queued request is marked terminal
  /// ('dead') and excluded from the pending queue. Without this cap a
  /// permanently-unreachable backend would keep failing requests in rotation
  /// forever, leaving the sync banner spinning indefinitely.
  static const int maxReplayAttempts = 5;

  /// Indicates whether an encryption key exists in secure storage.
  Future<bool> isEncrypted() async {
    return _encryptionService.hasEncryptionKey();
  }

  Future<void> ensureOfflineSyncTable() async {
    final db = await _openDb();
    db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sync (
        id TEXT PRIMARY KEY,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        headers_json TEXT NOT NULL,
        body_json TEXT,
        created_at TEXT NOT NULL,
        fingerprint TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_sync_status_created_at
      ON offline_sync(status, created_at)
    ''');
  }

  Future<String> upsertOfflineSyncOperation({
    required String id,
    required String method,
    required String url,
    required String headersJson,
    String? bodyJson,
    required String createdAtIso,
    required String fingerprint,
  }) async {
    await ensureOfflineSyncTable();
    final db = await _openDb();

    db.execute(
      '''
      INSERT OR IGNORE INTO offline_sync (
        id, method, url, headers_json, body_json, created_at, fingerprint
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        id,
        method,
        url,
        headersJson,
        bodyJson,
        createdAtIso,
        fingerprint,
      ],
    );

    final row = db.select(
      'SELECT id FROM offline_sync WHERE fingerprint = ? LIMIT 1',
      <Object?>[fingerprint],
    );

    if (row.isEmpty) {
      return id;
    }
    return row.first['id']?.toString() ?? id;
  }

  Future<List<OfflineSyncDbRow>> getPendingOfflineSyncQueue({
    int limit = 200,
  }) async {
    await ensureOfflineSyncTable();
    final db = await _openDb();
    final rows = db.select(
      '''
      SELECT
        id,
        fingerprint,
        method,
        url,
        headers_json,
        body_json,
        created_at,
        status,
        retry_count,
        last_error
      FROM offline_sync
      WHERE status IN ('pending', 'failed', 'syncing')
      ORDER BY created_at ASC, rowid ASC
      LIMIT ?
      ''',
      <Object?>[limit],
    );

    return rows.map(_mapRow).toList();
  }

  Future<int> getPendingOfflineSyncCount() async {
    await ensureOfflineSyncTable();
    final db = await _openDb();
    final rows = db.select(
      '''
      SELECT COUNT(*) AS count
      FROM offline_sync
      WHERE status IN ('pending', 'failed', 'syncing')
      ''',
    );
    if (rows.isEmpty) {
      return 0;
    }
    final value = rows.first['count'];
    return value is int ? value : int.tryParse(value.toString()) ?? 0;
  }

  Future<OfflineSyncDbRow?> getOfflineSyncById(String id) async {
    await ensureOfflineSyncTable();
    final db = await _openDb();
    final rows = db.select(
      '''
      SELECT
        id,
        fingerprint,
        method,
        url,
        headers_json,
        body_json,
        created_at,
        status,
        retry_count,
        last_error
      FROM offline_sync
      WHERE id = ?
      LIMIT 1
      ''',
      <Object?>[id],
    );

    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  Future<void> markOfflineSyncAsSyncing(String id) async {
    final db = await _openDb();
    db.execute(
      "UPDATE offline_sync SET status = 'syncing' WHERE id = ?",
      <Object?>[id],
    );
  }

  Future<void> markOfflineSyncAsFailed({
    required String id,
    required String errorMessage,
  }) async {
    final db = await _openDb();
    db.execute(
      '''
      UPDATE offline_sync
      SET
        retry_count = retry_count + 1,
        last_error = ?,
        status = CASE
          WHEN retry_count + 1 >= ? THEN 'dead'
          ELSE 'failed'
        END
      WHERE id = ?
      ''',
      <Object?>[errorMessage, maxReplayAttempts, id],
    );
  }

  Future<void> deleteOfflineSyncById(String id) async {
    final db = await _openDb();
    db.execute(
      'DELETE FROM offline_sync WHERE id = ?',
      <Object?>[id],
    );
  }

  Future<void> closeDb() async {
    _db?.dispose();
    _db = null;
  }

  Future<sqlite.Database> _openDb() async {
    if (_db != null) {
      return _db!;
    }

    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'careconnect_mobile.sqlite'));
    final encryptionKey = await _encryptionService.getOrCreateEncryptionKey();
    final db = sqlite.sqlite3.open(file.path);
    final escaped = _encryptionService.escapeForPragma(encryptionKey);
    db.execute("PRAGMA key = '$escaped';");
    db.execute('PRAGMA foreign_keys = ON;');
    _db = db;
    return db;
  }

  OfflineSyncDbRow _mapRow(sqlite.Row row) {
    final createdAtRaw = row['created_at']?.toString() ?? '';
    final retryRaw = row['retry_count'];
    return OfflineSyncDbRow(
      id: row['id']?.toString() ?? '',
      fingerprint: row['fingerprint']?.toString() ?? '',
      method: row['method']?.toString() ?? '',
      url: row['url']?.toString() ?? '',
      headersJson: row['headers_json']?.toString() ?? '{}',
      bodyJson: row['body_json']?.toString(),
      createdAt: DateTime.tryParse(createdAtRaw) ?? DateTime.now().toUtc(),
      status: row['status']?.toString() ?? 'pending',
      retryCount: retryRaw is int ? retryRaw : int.tryParse('$retryRaw') ?? 0,
      lastError: row['last_error']?.toString(),
    );
  }
}
