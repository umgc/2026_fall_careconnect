// Models for medication label photo capture (F-01, OCR + LLM prefill).

import 'medication-model.dart';

/// Statuses returned by the backend extract-photo endpoint.
class MedicationPhotoExtractionStatus {
  static const String prefilled = 'PREFILLED';
  static const String manualEntryRequired = 'MANUAL_ENTRY_REQUIRED';
}

/// Field keys returned by the backend extract-photo endpoint.
class MedicationPhotoFieldKey {
  static const String medicationName = 'medicationName';
  static const String dosage = 'dosage';
  static const String frequency = 'frequency';
  static const String medicationType = 'medicationType';
}

/// A single medication field, possibly prefilled from the label photo.
class MedicationPhotoExtractedField {
  final String key;
  final String label;
  final String value;

  /// True when the value was prefilled by AI rather than typed by a person.
  final bool machineGenerated;

  const MedicationPhotoExtractedField({
    required this.key,
    required this.label,
    required this.value,
    required this.machineGenerated,
  });

  factory MedicationPhotoExtractedField.fromJson(Map<String, dynamic> json) {
    return MedicationPhotoExtractedField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '',
      machineGenerated: json['machineGenerated'] == true,
    );
  }
}

/// Extraction result for one label photo: either AI-prefilled draft fields,
/// or no values when the pipeline fell back to manual entry.
class MedicationPhotoExtractionResult {
  final String status;
  final String? message;
  final List<MedicationPhotoExtractedField> fields;

  const MedicationPhotoExtractionResult({
    required this.status,
    this.message,
    required this.fields,
  });

  bool get manualEntryRequired =>
      status == MedicationPhotoExtractionStatus.manualEntryRequired;

  /// The machine-generated value for [key], or null when it was not read.
  String? prefilledValue(String key) {
    for (final field in fields) {
      if (field.key == key && field.machineGenerated && field.value.isNotEmpty) {
        return field.value;
      }
    }
    return null;
  }

  factory MedicationPhotoExtractionResult.fromJson(Map<String, dynamic> json) {
    final fieldsList = (json['fields'] as List?) ?? const [];
    return MedicationPhotoExtractionResult(
      status: json['status'] as String? ??
          MedicationPhotoExtractionStatus.manualEntryRequired,
      message: json['message'] as String?,
      fields: fieldsList
          .whereType<Map<String, dynamic>>()
          .map(MedicationPhotoExtractedField.fromJson)
          .toList(),
    );
  }

  /// Local fallback to manual entry when the backend is unreachable or the
  /// photo could not be read.
  factory MedicationPhotoExtractionResult.manualFallback({String? message}) {
    return MedicationPhotoExtractionResult(
      status: MedicationPhotoExtractionStatus.manualEntryRequired,
      message: message,
      fields: const [],
    );
  }
}

/// Maps an extracted backend MedicationType constant to the frontend enum.
/// Unknown values return null so the review form leaves the type blank.
MedicationType? medicationTypeFromExtracted(String? value) =>
    medicationTypeFromWire(value);
