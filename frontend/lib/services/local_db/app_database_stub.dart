import 'offline_sync_row.dart';

/// Session-scoped implementation of AppDatabase for web.
///
/// Queued writes remain in memory so they can replay after connectivity returns
/// without persisting patient request data to unencrypted browser storage.
class AppDatabase {
  AppDatabase({dynamic encryptionService});

  final List<OfflineSyncDbRow> _offlineSyncQueue = <OfflineSyncDbRow>[];

  static const Set<String> _actionableStatuses = <String>{
    'pending',
    'failed',
    'syncing',
  };

  /// Indicates whether an encryption key exists (always false on web)
  Future<bool> isEncrypted() async {
    return false;
  }

  /// Web queue storage is initialized with this instance.
  Future<void> ensureOfflineSyncTable() async {
    // No-op: the session queue is ready when AppDatabase is constructed.
  }

  /// Add an offline sync operation unless its fingerprint is already queued.
  Future<String> upsertOfflineSyncOperation({
    required String id,
    required String method,
    required String url,
    required String headersJson,
    String? bodyJson,
    required String createdAtIso,
    required String fingerprint,
  }) async {
    for (final row in _offlineSyncQueue) {
      if (row.fingerprint == fingerprint) {
        return row.id;
      }
    }

    _offlineSyncQueue.add(
      OfflineSyncDbRow(
        id: id,
        fingerprint: fingerprint,
        method: method,
        url: url,
        headersJson: headersJson,
        bodyJson: bodyJson,
        createdAt: DateTime.tryParse(createdAtIso) ?? DateTime.now().toUtc(),
        status: 'pending',
        retryCount: 0,
        lastError: null,
      ),
    );
    return id;
  }

  /// Get actionable offline sync rows in creation order.
  Future<List<OfflineSyncDbRow>> getPendingOfflineSyncQueue({
    int limit = 200,
  }) async {
    final rows = _offlineSyncQueue
        .where((row) => _actionableStatuses.contains(row.status))
        .toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return rows.take(limit).toList();
  }

  /// Get the number of actionable offline sync rows.
  Future<int> getPendingOfflineSyncCount() async {
    return _offlineSyncQueue
        .where((row) => _actionableStatuses.contains(row.status))
        .length;
  }

  /// Get a specific offline sync row by ID.
  Future<OfflineSyncDbRow?> getOfflineSyncById(String id) async {
    for (final row in _offlineSyncQueue) {
      if (row.id == id) {
        return row;
      }
    }
    return null;
  }

  /// Mark an offline sync as syncing.
  Future<void> markOfflineSyncAsSyncing(String id) async {
    _replaceRow(id, status: 'syncing');
  }

  /// Mark an offline sync as failed.
  Future<void> markOfflineSyncAsFailed({
    required String id,
    required String errorMessage,
  }) async {
    final index = _offlineSyncQueue.indexWhere((row) => row.id == id);
    if (index == -1) {
      return;
    }
    final row = _offlineSyncQueue[index];
    _offlineSyncQueue[index] = _copyRow(
      row,
      status: 'failed',
      retryCount: row.retryCount + 1,
      lastError: errorMessage,
    );
  }

  /// Delete an offline sync row by ID.
  Future<void> deleteOfflineSyncById(String id) async {
    _offlineSyncQueue.removeWhere((row) => row.id == id);
  }

  /// Close the database connection (no-op on web)
  Future<void> closeDb() async {
    // No-op on web
  }

  void _replaceRow(String id, {required String status}) {
    final index = _offlineSyncQueue.indexWhere((row) => row.id == id);
    if (index == -1) {
      return;
    }
    _offlineSyncQueue[index] = _copyRow(
      _offlineSyncQueue[index],
      status: status,
    );
  }

  OfflineSyncDbRow _copyRow(
    OfflineSyncDbRow row, {
    String? status,
    int? retryCount,
    String? lastError,
  }) {
    return OfflineSyncDbRow(
      id: row.id,
      fingerprint: row.fingerprint,
      method: row.method,
      url: row.url,
      headersJson: row.headersJson,
      bodyJson: row.bodyJson,
      createdAt: row.createdAt,
      status: status ?? row.status,
      retryCount: retryCount ?? row.retryCount,
      lastError: lastError ?? row.lastError,
    );
  }
}
