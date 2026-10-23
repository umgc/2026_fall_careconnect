// lib/features/virtual-check-in/pages/answer_builders.dart

import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_model.dart';

AnswerItem buildAnswerFromUi({
  required VirtualCheckInQuestion q,
  String? textValue,
  bool? boolValue,
  num? numValue,
}) {
  final qid = int.tryParse(q.id);
  if (qid == null) {
    throw ArgumentError('Invalid question id: ${q.id}');
  }

  switch (q.type) {
    case CheckInQuestionType.textInput:
      if (textValue == null || textValue.isEmpty) {
        throw ArgumentError('Missing text answer for question ${q.id}');
      }
      return AnswerItem.text(questionId: qid, value: textValue);

    case CheckInQuestionType.yesNo:
      if (boolValue == null) {
        throw ArgumentError('Missing boolean answer for question ${q.id}');
      }
      return AnswerItem.boolean(questionId: qid, value: boolValue);

    case CheckInQuestionType.numerical:
      if (numValue == null) {
        throw ArgumentError('Missing numeric answer for question ${q.id}');
      }
      return AnswerItem.number(questionId: qid, value: numValue);
  }

  // Unreachable but satisfies analyzer in older SDKs
  // ignore: dead_code
  throw StateError('Unhandled question type: ${q.type}');
}
