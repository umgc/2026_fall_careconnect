// Tests for buildAnswerFromUi
// (lib/features/health/virtual_check_in/presentation/widgets/answer_builders.dart)

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/answer_builders.dart';

VirtualCheckInQuestion _q(String id, CheckInQuestionType type) =>
    VirtualCheckInQuestion(id: id, type: type, required: true, text: 'Q?');

void main() {
  group('buildAnswerFromUi', () {
    // ── textInput ───────────────────────────────────────────────────────────
    test('returns AnswerItem with valueText for textInput question', () {
      final q = _q('1', CheckInQuestionType.textInput);
      final answer = buildAnswerFromUi(q: q, textValue: 'Hello');
      expect(answer.questionId, 1);
      expect(answer.valueText, 'Hello');
      expect(answer.valueBoolean, isNull);
      expect(answer.valueNumber, isNull);
    });

    test('throws ArgumentError when textValue is null for textInput', () {
      final q = _q('2', CheckInQuestionType.textInput);
      expect(
        () => buildAnswerFromUi(q: q, textValue: null),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when textValue is empty for textInput', () {
      final q = _q('3', CheckInQuestionType.textInput);
      expect(
        () => buildAnswerFromUi(q: q, textValue: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── yesNo ───────────────────────────────────────────────────────────────
    test('returns AnswerItem with valueBoolean true for yesNo question', () {
      final q = _q('4', CheckInQuestionType.yesNo);
      final answer = buildAnswerFromUi(q: q, boolValue: true);
      expect(answer.questionId, 4);
      expect(answer.valueBoolean, isTrue);
      expect(answer.valueText, isNull);
      expect(answer.valueNumber, isNull);
    });

    test('returns AnswerItem with valueBoolean false for yesNo question', () {
      final q = _q('5', CheckInQuestionType.yesNo);
      final answer = buildAnswerFromUi(q: q, boolValue: false);
      expect(answer.valueBoolean, isFalse);
    });

    test('throws ArgumentError when boolValue is null for yesNo', () {
      final q = _q('6', CheckInQuestionType.yesNo);
      expect(
        () => buildAnswerFromUi(q: q, boolValue: null),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── numerical ───────────────────────────────────────────────────────────
    test('returns AnswerItem with valueNumber for numerical question', () {
      final q = _q('7', CheckInQuestionType.numerical);
      final answer = buildAnswerFromUi(q: q, numValue: 42);
      expect(answer.questionId, 7);
      expect(answer.valueNumber, 42);
      expect(answer.valueText, isNull);
      expect(answer.valueBoolean, isNull);
    });

    test('returns AnswerItem with decimal valueNumber for numerical question', () {
      final q = _q('8', CheckInQuestionType.numerical);
      final answer = buildAnswerFromUi(q: q, numValue: 3.14);
      expect(answer.valueNumber, 3.14);
    });

    test('throws ArgumentError when numValue is null for numerical', () {
      final q = _q('9', CheckInQuestionType.numerical);
      expect(
        () => buildAnswerFromUi(q: q, numValue: null),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── invalid question id ─────────────────────────────────────────────────
    test('throws ArgumentError when question id is not a valid integer', () {
      final q = _q('not-an-int', CheckInQuestionType.textInput);
      expect(
        () => buildAnswerFromUi(q: q, textValue: 'Hello'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ── questionId parsed correctly ─────────────────────────────────────────
    test('parses multi-digit question id correctly', () {
      final q = _q('123', CheckInQuestionType.yesNo);
      final answer = buildAnswerFromUi(q: q, boolValue: true);
      expect(answer.questionId, 123);
    });
  });
}
