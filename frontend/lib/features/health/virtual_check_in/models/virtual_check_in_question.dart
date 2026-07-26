// lib/features/health/caregiver-patient-list/models/virtual_check_in_question.dart

enum CheckInQuestionType { numerical, yesNo, textInput }

class VirtualCheckInQuestion {
  final String id;
  final CheckInQuestionType type;
  final bool required;
  final String text;
  final String formKey;
  final int formVersion;
  final String sectionKey;
  final String? fieldKey;
  final double? scoreWeight;

  const VirtualCheckInQuestion({
    required this.id,
    required this.type,
    required this.required,
    required this.text,
    this.formKey = 'virtual-checkin',
    this.formVersion = 1,
    this.sectionKey = 'general',
    this.fieldKey,
    this.scoreWeight,
  });
}
