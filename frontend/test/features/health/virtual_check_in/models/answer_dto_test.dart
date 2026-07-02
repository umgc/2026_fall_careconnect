import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';

void main() {
  group('AnswerUpsertRequestDTO', () {
    test('fromInput with TEXT type creates valueText', () {
      // Arrange
      const input = 'My answer text';

      // Act
      final answer = AnswerUpsertRequestDTO.fromInput(
        questionId: 1,
        type: BackendQuestionType.text,
        value: input,
      );

      // Assert
      expect(answer.questionId, 1);
      expect(answer.valueText, 'My answer text');
      expect(answer.valueBoolean, isNull);
      expect(answer.valueNumber, isNull);
    });

    test('fromInput with YES_NO type creates valueBoolean', () {
      // Act
      final answer = AnswerUpsertRequestDTO.fromInput(
        questionId: 2,
        type: BackendQuestionType.yesNo,
        value: true,
      );

      // Assert
      expect(answer.questionId, 2);
      expect(answer.valueBoolean, true);
      expect(answer.valueText, isNull);
      expect(answer.valueNumber, isNull);
    });

    test('fromInput with TRUE_FALSE type creates valueBoolean', () {
      // Act
      final answer = AnswerUpsertRequestDTO.fromInput(
        questionId: 3,
        type: BackendQuestionType.trueFalse,
        value: false,
      );

      // Assert
      expect(answer.valueBoolean, false);
    });

    test('fromInput with NUMBER type creates valueNumber', () {
      // Act
      final answer = AnswerUpsertRequestDTO.fromInput(
        questionId: 4,
        type: BackendQuestionType.number,
        value: 42.5,
      );

      // Assert
      expect(answer.questionId, 4);
      expect(answer.valueNumber, 42.5);
      expect(answer.valueText, isNull);
      expect(answer.valueBoolean, isNull);
    });

    test('toJson includes all non-null fields', () {
      // Arrange
      final answer = AnswerUpsertRequestDTO(
        questionId: 1,
        valueText: 'test',
        valueBoolean: null,
        valueNumber: null,
      );

      // Act
      final json = answer.toJson();

      // Assert
      expect(json['questionId'], 1);
      expect(json['valueText'], 'test');
      expect(json.containsKey('valueBoolean'), false);
      expect(json.containsKey('valueNumber'), false);
    });

    test('toJson with number value', () {
      // Arrange
      final answer = AnswerUpsertRequestDTO(
        questionId: 2,
        valueNumber: 100,
      );

      // Act
      final json = answer.toJson();

      // Assert
      expect(json['questionId'], 2);
      expect(json['valueNumber'], 100);
      expect(json.containsKey('valueText'), false);
    });
  });

  group('SubmitAnswersRequestDTO', () {
    test('toJson serializes list of answers', () {
      // Arrange
      final answers = [
        AnswerUpsertRequestDTO(questionId: 1, valueText: 'answer1'),
        AnswerUpsertRequestDTO(questionId: 2, valueBoolean: true),
      ];
      final request = SubmitAnswersRequestDTO(answers: answers);

      // Act
      final json = request.toJson();

      // Assert
      expect(json['answers'], isA<List>());
      expect(json['answers']?.length, 2);
      expect(json['answers']?[0]['questionId'], 1);
      expect(json['answers']?[1]['questionId'], 2);
    });

    test('toJson with empty answers list', () {
      // Arrange
      final request = SubmitAnswersRequestDTO(answers: []);

      // Act
      final json = request.toJson();

      // Assert
      expect(json['answers'], []);
    });
  });

  group('SubmitAnswersResponseDTO', () {
    test('fromJson parses response correctly', () {
      // Arrange
      final json = {
        'checkInId': 123,
        'acceptedAnswerCount': 5,
        'submittedAt': '2024-01-15T10:30:00Z',
      };

      // Act
      final response = SubmitAnswersResponseDTO.fromJson(json);

      // Assert
      expect(response.checkInId, 123);
      expect(response.acceptedAnswerCount, 5);
      expect(response.submittedAt, isNotNull);
    });

    test('fromJson with valid response', () {
      // Arrange
      final json = {
        'checkInId': 123,
        'acceptedAnswerCount': 3,
        'submittedAt': '2024-01-15T10:30:00Z',
      };

      // Act
      final response = SubmitAnswersResponseDTO.fromJson(json);

      // Assert
      expect(response.checkInId, 123);
      expect(response.acceptedAnswerCount, 3);
      expect(response.submittedAt, isNotNull);
    });

    test('fromJson handles missing fields gracefully', () {
      // Arrange
      final json = {'checkInId': 456};

      // Act
      final response = SubmitAnswersResponseDTO.fromJson(json);

      // Assert
      expect(response.checkInId, 456);
      expect(response.acceptedAnswerCount, 0);
      expect(response.submittedAt, isNull);
    });
  });
}
