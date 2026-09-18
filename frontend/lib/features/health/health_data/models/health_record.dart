// health_record.dart
//
// SHARED record shape for the unified Health Data experience.
// Every connected source (Epic, Cerner, Athena, Medicare) maps its own data
// into this one shape. This is a DISPLAY contract, not the backend model.

enum RecordSource {
  epic,
  cerner,
  athena,
  medicare;

  String get label {
    switch (this) {
      case RecordSource.epic:
        return 'Epic';
      case RecordSource.cerner:
        return 'Cerner';
      case RecordSource.athena:
        return 'Athena';
      case RecordSource.medicare:
        return 'Medicare';
    }
  }

  String get badge => 'From $label';
}

enum RecordType {
  medication,
  condition,
  allergy,
  appointment,
  clinicalRecord,
  claimService,
  other;

  String get label {
    switch (this) {
      case RecordType.medication:
        return 'Medication';
      case RecordType.condition:
        return 'Condition';
      case RecordType.allergy:
        return 'Allergy';
      case RecordType.appointment:
        return 'Appointment';
      case RecordType.clinicalRecord:
        return 'Clinical Record';
      case RecordType.claimService:
        return 'Claim / Service';
      case RecordType.other:
        return 'Record';
    }
  }
}

class RecordDetail {
  final String label;
  final String value;

  const RecordDetail(this.label, this.value);

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  factory RecordDetail.fromJson(Map<String, dynamic> json) => RecordDetail(
        json['label'] as String? ?? '',
        json['value'] as String? ?? '',
      );
}

class HealthRecord {
  final String id;
  final List<RecordSource> sources;
  final RecordType type;
  final String title;
  final DateTime? date;
  final List<RecordDetail> details;
  final String? status;

  const HealthRecord({
    required this.id,
    required this.sources,
    required this.type,
    required this.title,
    this.date,
    this.details = const [],
    this.status,
  });

  factory HealthRecord.single({
    required String id,
    required RecordSource source,
    required RecordType type,
    required String title,
    DateTime? date,
    List<RecordDetail> details = const [],
    String? status,
  }) {
    return HealthRecord(
      id: id,
      sources: [source],
      type: type,
      title: title,
      date: date,
      details: details,
      status: status,
    );
  }

  RecordSource get primarySource => sources.first;
  bool get isMultiSource => sources.length > 1;

  HealthRecord copyWith({
    String? id,
    List<RecordSource>? sources,
    RecordType? type,
    String? title,
    DateTime? date,
    List<RecordDetail>? details,
    String? status,
  }) {
    return HealthRecord(
      id: id ?? this.id,
      sources: sources ?? this.sources,
      type: type ?? this.type,
      title: title ?? this.title,
      date: date ?? this.date,
      details: details ?? this.details,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sources': sources.map((s) => s.name).toList(),
        'type': type.name,
        'title': title,
        'date': date?.toIso8601String(),
        'details': details.map((d) => d.toJson()).toList(),
        'status': status,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> json) {
    return HealthRecord(
      id: json['id'] as String? ?? '',
      sources: ((json['sources'] as List?) ?? [])
          .map((s) => RecordSource.values.firstWhere(
                (e) => e.name == s,
                orElse: () => RecordSource.epic,
              ))
          .toList(),
      type: RecordType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecordType.other,
      ),
      title: json['title'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      details: ((json['details'] as List?) ?? [])
          .map((d) => RecordDetail.fromJson(d as Map<String, dynamic>))
          .toList(),
      status: json['status'] as String?,
    );
  }
}
