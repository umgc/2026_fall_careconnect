class FeatureTrend {
  final String feature;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<DailyFeatureCount> dailyCounts;

  const FeatureTrend({
    required this.feature,
    required this.periodStart,
    required this.periodEnd,
    required this.dailyCounts,
  });

  factory FeatureTrend.fromJson(Map<String, dynamic> json) {
    return FeatureTrend(
      feature: json['feature'] as String? ?? '',
      periodStart: DateTime.parse(json['periodStart'] as String),
      periodEnd: DateTime.parse(json['periodEnd'] as String),
      dailyCounts: _parseDailyCounts(json['dailyCounts']),
    );
  }

  static List<DailyFeatureCount> _parseDailyCounts(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DailyFeatureCount.fromJson)
        .toList(growable: false);
  }
}

class DailyFeatureCount {
  final DateTime date;
  final int count;

  const DailyFeatureCount({required this.date, required this.count});

  factory DailyFeatureCount.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as String? ?? '';
    return DailyFeatureCount(
      date: DateTime.parse('${rawDate}T00:00:00.000Z'),
      count: _asInt(json['count']),
    );
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}
