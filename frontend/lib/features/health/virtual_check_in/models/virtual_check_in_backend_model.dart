enum BackendQuestionType { TEXT, YES_NO, TRUE_FALSE, NUMBER }

extension BackendQuestionTypeX on BackendQuestionType {
  static BackendQuestionType parse(Object? raw) {
    if (raw == null) throw const FormatException('Question type is null');
    final s = raw.toString().trim().toUpperCase();
    switch (s) {
      case 'TEXT':
        return BackendQuestionType.TEXT;
      case 'YES_NO':
        return BackendQuestionType.YES_NO;
      case 'TRUE_FALSE':
        return BackendQuestionType.TRUE_FALSE;
      case 'NUMBER':
        return BackendQuestionType.NUMBER;
      default:
        throw FormatException('Unknown question type: $raw');
    }
  }

  String get nameUpper => toString().split('.').last; // e.g., TEXT
}

/// One question attached to a specific check-in (already ordered + required flag)
class BackendQuestionDto {
  final int id;
  final String prompt;
  final BackendQuestionType type;
  final bool required;
  final int ordinal;

  const BackendQuestionDto({
    required this.id,
    required this.prompt,
    required this.type,
    required this.required,
    required this.ordinal,
  });

  factory BackendQuestionDto.fromJson(Map<String, dynamic> j) {
    // Be tolerant of id coming as int or string
    final idRaw = j['id'];
    final id = (idRaw is int) ? idRaw : int.parse(idRaw.toString());

    return BackendQuestionDto(
      id: id,
      prompt: (j['prompt'] ?? '').toString(),
      type: BackendQuestionTypeX.parse(j['type']),
      required: j['required'] == true || j['required']?.toString() == 'true',
      ordinal: j['ordinal'] is int
          ? j['ordinal'] as int
          : int.parse(j['ordinal'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'type': type.nameUpper,
        'required': required,
        'ordinal': ordinal,
      };
}

/// Payload for POST /api/checkins/{checkInId}/answers
class SubmitAnswersRequest {
  final List<AnswerItem> answers;
  const SubmitAnswersRequest(this.answers);

  Map<String, dynamic> toJson() => {
        'answers': answers.map((a) => a.toJson()).toList(),
      };
}

/// Exactly one of valueText / valueBoolean / valueNumber must be set.
class AnswerItem {
  final int questionId;
  final String? valueText;
  final bool? valueBoolean;
  final num? valueNumber;

  const AnswerItem._({
    required this.questionId,
    this.valueText,
    this.valueBoolean,
    this.valueNumber,
  });

  /// Helpers to create a valid item for each question type
  factory AnswerItem.text({required int questionId, required String value}) =>
      AnswerItem._(questionId: questionId, valueText: value);

  factory AnswerItem.boolean({required int questionId, required bool value}) =>
      AnswerItem._(questionId: questionId, valueBoolean: value);

  factory AnswerItem.number({required int questionId, required num value}) =>
      AnswerItem._(questionId: questionId, valueNumber: value);

  /// Optional: validate that exactly one value is set (mirrors backend rule)
  void assertExactlyOneValue() {
    final count = (valueText != null ? 1 : 0) +
        (valueBoolean != null ? 1 : 0) +
        (valueNumber != null ? 1 : 0);
    if (count != 1) {
      throw StateError(
          'Exactly one of valueText/valueBoolean/valueNumber must be set.');
    }
  }

  Map<String, dynamic> toJson() {
    // (Uncomment next line if you want client-side validation before sending)
    // assertExactlyOneValue();
    return {
      'questionId': questionId,
      if (valueText != null) 'valueText': valueText,
      if (valueBoolean != null) 'valueBoolean': valueBoolean,
      if (valueNumber != null) 'valueNumber': valueNumber,
    };
  }
}
