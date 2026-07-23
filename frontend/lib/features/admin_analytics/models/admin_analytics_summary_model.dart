class AdminAnalyticsSummary {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int totalEvents;
  final int sessionCount;
  final List<EventNameCount> eventCountsByName;
  final List<FeatureUsageCount> topFeatures;
  final SyncMetrics syncMetrics;
  final ErrorMetrics errorMetrics;

  const AdminAnalyticsSummary({
    required this.periodStart,
    required this.periodEnd,
    required this.totalEvents,
    required this.sessionCount,
    required this.eventCountsByName,
    required this.topFeatures,
    required this.syncMetrics,
    required this.errorMetrics,
  });

  factory AdminAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AdminAnalyticsSummary(
      periodStart: DateTime.parse(json['periodStart'] as String),
      periodEnd: DateTime.parse(json['periodEnd'] as String),
      totalEvents: _asInt(json['totalEvents']),
      sessionCount: _asInt(json['sessionCount']),
      eventCountsByName: _parseList(
        json['eventCountsByName'],
        EventNameCount.fromJson,
      ),
      topFeatures: _parseList(json['topFeatures'], FeatureUsageCount.fromJson),
      syncMetrics: SyncMetrics.fromJson(
        json['syncMetrics'] as Map<String, dynamic>? ?? {},
      ),
      errorMetrics: ErrorMetrics.fromJson(
        json['errorMetrics'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}

class EventNameCount {
  final String eventName;
  final int count;

  const EventNameCount({required this.eventName, required this.count});

  factory EventNameCount.fromJson(Map<String, dynamic> json) {
    return EventNameCount(
      eventName: json['eventName'] as String? ?? '',
      count: AdminAnalyticsSummary._asInt(json['count']),
    );
  }
}

class FeatureUsageCount {
  final String feature;
  final int count;

  const FeatureUsageCount({required this.feature, required this.count});

  factory FeatureUsageCount.fromJson(Map<String, dynamic> json) {
    return FeatureUsageCount(
      feature: json['feature'] as String? ?? '',
      count: AdminAnalyticsSummary._asInt(json['count']),
    );
  }
}

class SyncMetrics {
  final int started;
  final int completed;
  final int failedEvents;
  final int attempted;
  final int succeeded;
  final int failed;
  final double? successRate;

  const SyncMetrics({
    required this.started,
    required this.completed,
    required this.failedEvents,
    required this.attempted,
    required this.succeeded,
    required this.failed,
    this.successRate,
  });

  factory SyncMetrics.fromJson(Map<String, dynamic> json) {
    return SyncMetrics(
      started: AdminAnalyticsSummary._asInt(json['started']),
      completed: AdminAnalyticsSummary._asInt(json['completed']),
      failedEvents: AdminAnalyticsSummary._asInt(json['failedEvents']),
      attempted: AdminAnalyticsSummary._asInt(json['attempted']),
      succeeded: AdminAnalyticsSummary._asInt(json['succeeded']),
      failed: AdminAnalyticsSummary._asInt(json['failed']),
      successRate: json['successRate'] == null
          ? null
          : (json['successRate'] as num).toDouble(),
    );
  }
}

class ErrorMetrics {
  final int totalErrors;
  final List<EndpointErrorCount> byEndpointBucket;

  const ErrorMetrics({
    required this.totalErrors,
    required this.byEndpointBucket,
  });

  factory ErrorMetrics.fromJson(Map<String, dynamic> json) {
    return ErrorMetrics(
      totalErrors: AdminAnalyticsSummary._asInt(json['totalErrors']),
      byEndpointBucket: AdminAnalyticsSummary._parseList(
        json['byEndpointBucket'],
        EndpointErrorCount.fromJson,
      ),
    );
  }
}

class EndpointErrorCount {
  final String endpoint;
  final int count;
  final double rate;

  const EndpointErrorCount({
    required this.endpoint,
    required this.count,
    required this.rate,
  });

  factory EndpointErrorCount.fromJson(Map<String, dynamic> json) {
    return EndpointErrorCount(
      endpoint: json['endpoint'] as String? ?? '',
      count: AdminAnalyticsSummary._asInt(json['count']),
      rate: json['rate'] == null ? 0.0 : (json['rate'] as num).toDouble(),
    );
  }
}
