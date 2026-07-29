import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';


class BackendQuestionDto {
  final int? id;
  final String prompt;
  final BackendQuestionType type;
  final bool required;
  final bool active;
  final int ordinal;
  final String formKey;
  final int formVersion;
  final String sectionKey;
  final String? fieldKey;
  final double? scoreWeight;

  const BackendQuestionDto({
    this.id,
    required this.prompt,
    required this.type,
    required this.required,
    required this.active,
    required this.ordinal,
    this.formKey = 'virtual-checkin',
    this.formVersion = 1,
    this.sectionKey = 'general',
    this.fieldKey,
    this.scoreWeight,
  });

  factory BackendQuestionDto.fromJson(Map<String, dynamic> json) {
    return BackendQuestionDto(
      id: json['id'] is int ? json['id'] as int : (json['id'] as num?)?.toInt(),
      prompt: (json['prompt'] ?? '') as String,
      type: BackendQuestionType.fromWire(json['type'] as String?),
      required: (json['required'] as bool?) ?? false,
      active: (json['active'] as bool?) ?? true,
      ordinal: json['ordinal'] is int
          ? json['ordinal'] as int
          : (json['ordinal'] as num?)?.toInt() ?? 0,
      formKey: (json['formKey'] as String?) ?? 'virtual-checkin',
      formVersion: json['formVersion'] is int
          ? json['formVersion'] as int
          : (json['formVersion'] as num?)?.toInt() ?? 1,
      sectionKey: (json['sectionKey'] as String?) ?? 'general',
      fieldKey: json['fieldKey'] as String?,
      scoreWeight: (json['scoreWeight'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'prompt': prompt,
      'type': type.toWire(), // MUST match backend enum string
      'required': required,
      'active': active,
      'ordinal': ordinal,
      if (formKey != 'virtual-checkin') 'formKey': formKey,
      if (formVersion != 1) 'formVersion': formVersion,
      if (sectionKey != 'general') 'sectionKey': sectionKey,
      if (fieldKey != null) 'fieldKey': fieldKey,
      if (scoreWeight != null) 'scoreWeight': scoreWeight,
    };
  }

  BackendQuestionDto copyWith({
    int? id,
    String? prompt,
    BackendQuestionType? type,
    bool? required,
    bool? active,
    int? ordinal,
    String? formKey,
    int? formVersion,
    String? sectionKey,
    String? fieldKey,
    double? scoreWeight,
  }) {
    return BackendQuestionDto(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      type: type ?? this.type,
      required: required ?? this.required,
      active: active ?? this.active,
      ordinal: ordinal ?? this.ordinal,
      formKey: formKey ?? this.formKey,
      formVersion: formVersion ?? this.formVersion,
      sectionKey: sectionKey ?? this.sectionKey,
      fieldKey: fieldKey ?? this.fieldKey,
      scoreWeight: scoreWeight ?? this.scoreWeight,
    );
  }
}
