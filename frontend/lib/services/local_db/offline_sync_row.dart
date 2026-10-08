class OfflineSyncStatus {
  const OfflineSyncStatus._();

  static const String pending = 'pending';
  static const String failed = 'failed';
  static const String syncing = 'syncing';

  static const Set<String> actionable = <String>{
    pending,
    failed,
    syncing,
  };
}

class OfflineSyncDbRow {
  const OfflineSyncDbRow({
    required this.id,
    required this.fingerprint,
    required this.method,
    required this.url,
    required this.headersJson,
    required this.bodyJson,
    required this.createdAt,
    required this.status,
    required this.retryCount,
    required this.lastError,
  });

  final String id;
  final String fingerprint;
  final String method;
  final String url;
  final String headersJson;
  final String? bodyJson;
  final DateTime createdAt;
  final String status;
  final int retryCount;
  final String? lastError;

  static const Object _unchangedLastError = Object();

  OfflineSyncDbRow copyWith({
    String? status,
    int? retryCount,
    Object? lastError = _unchangedLastError,
  }) {
    return OfflineSyncDbRow(
      id: id,
      fingerprint: fingerprint,
      method: method,
      url: url,
      headersJson: headersJson,
      bodyJson: bodyJson,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: identical(lastError, _unchangedLastError)
          ? this.lastError
          : lastError as String?,
    );
  }
}
