class DashboardAnalytics {
  final double? adherenceRate;
  final double? avgHeartRate;
  final double? avgSpo2;
  final double? avgSystolic;
  final double? avgDiastolic;
  final double? avgWeight;
  final double? avgMoodValue;
  final double? avgPainValue;
  final List<double>? moodValues;
  final List<double>? painValues;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  DashboardAnalytics({
    this.adherenceRate,
    this.avgHeartRate,
    this.avgSpo2,
    this.avgSystolic,
    this.avgDiastolic,
    this.avgWeight,
    this.avgMoodValue,
    this.avgPainValue,
    this.moodValues,
    this.painValues,
    this.periodStart,
    this.periodEnd,
  });

  factory DashboardAnalytics.fromJson(Map<String, dynamic> json) {
    return DashboardAnalytics(
      adherenceRate: json['adherenceRate']?.toDouble(),
      avgHeartRate: json['avgHeartRate']?.toDouble(),
      avgSpo2: json['avgSpo2']?.toDouble(),
      avgSystolic: json['avgSystolic']?.toDouble(),
      avgDiastolic: json['avgDiastolic']?.toDouble(),
      avgWeight: json['avgWeight']?.toDouble(),
      // Map the correct API field names to model properties
      avgMoodValue: json['avgMood']?.toDouble(),
      avgPainValue: json['avgPain']?.toDouble(),
      moodValues: json['moodValues'] != null
          ? List<double>.from(
              (json['moodValues'] as List).map((e) => e.toDouble()),
            )
          : null,
      painValues: json['painValues'] != null
          ? List<double>.from(
              (json['painValues'] as List).map((e) => e.toDouble()),
            )
          : null,
      periodStart: json['periodStart'] != null
          ? DateTime.parse(json['periodStart'])
          : null,
      periodEnd:
          json['periodEnd'] != null ? DateTime.parse(json['periodEnd']) : null,
    );
  }
}
