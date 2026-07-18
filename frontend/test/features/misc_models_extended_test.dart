// Tests for Patient, BackendQuestionDto, BackendQuestionType,
// and PostWithCommentCountDto models.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/models/patient-info.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';
import 'package:care_connect_app/features/social/presentation/model/PostWithCommentCountDto.dart';

void main() {
  // =========================================================================
  // Patient
  // =========================================================================

  group('Patient', () {
    test('constructor stores all required fields', () {
      final patient = Patient(
        id: '42',
        firstName: 'John',
        lastName: 'Doe',
        lastUpdated: DateTime(2026, 3, 17),
        statusMessage: 'Feeling better today',
        nextCheckIn: DateTime(2026, 3, 18, 10, 0),
        mood: 'Good',
        moodEmoji: '😊',
        isUrgent: false,
      );

      expect(patient.id, '42');
      expect(patient.firstName, 'John');
      expect(patient.lastName, 'Doe');
      expect(patient.mood, 'Good');
      expect(patient.moodEmoji, '😊');
      expect(patient.isUrgent, false);
    });

    test('fullName combines first and last name', () {
      final patient = Patient(
        id: '1',
        firstName: 'Alice',
        lastName: 'Smith',
        lastUpdated: DateTime.now(),
        statusMessage: '',
        nextCheckIn: DateTime.now(),
        mood: 'Fair',
        moodEmoji: '😐',
        isUrgent: false,
      );
      expect(patient.fullName, 'Alice Smith');
    });

    test('messageCount defaults to 0', () {
      final patient = Patient(
        id: '1',
        firstName: 'Test',
        lastName: 'Patient',
        lastUpdated: DateTime.now(),
        statusMessage: '',
        nextCheckIn: DateTime.now(),
        mood: 'Good',
        moodEmoji: '😊',
        isUrgent: false,
      );
      expect(patient.messageCount, 0);
    });

    test('messageCount can be set', () {
      final patient = Patient(
        id: '1',
        firstName: 'Test',
        lastName: 'Patient',
        lastUpdated: DateTime.now(),
        statusMessage: '',
        nextCheckIn: DateTime.now(),
        mood: 'Good',
        moodEmoji: '😊',
        isUrgent: false,
        messageCount: 5,
      );
      expect(patient.messageCount, 5);
    });

    test('patientUserId is optional', () {
      final patient = Patient(
        id: '1',
        patientUserId: 99,
        firstName: 'Test',
        lastName: 'User',
        lastUpdated: DateTime.now(),
        statusMessage: '',
        nextCheckIn: DateTime.now(),
        mood: 'Good',
        moodEmoji: '😊',
        isUrgent: false,
      );
      expect(patient.patientUserId, 99);
    });

    test('urgent patient flag', () {
      final patient = Patient(
        id: '1',
        firstName: 'Urgent',
        lastName: 'Patient',
        lastUpdated: DateTime.now(),
        statusMessage: 'Needs immediate attention',
        nextCheckIn: DateTime.now(),
        mood: 'Poor',
        moodEmoji: '😰',
        isUrgent: true,
      );
      expect(patient.isUrgent, true);
    });
  });

  // =========================================================================
  // BackendQuestionType
  // =========================================================================

  group('BackendQuestionType', () {
    test('fromWire TEXT returns text', () {
      expect(BackendQuestionType.fromWire('TEXT'), BackendQuestionType.text);
    });

    test('fromWire YES_NO returns yesNo', () {
      expect(BackendQuestionType.fromWire('YES_NO'), BackendQuestionType.yesNo);
    });

    test('fromWire TRUE_FALSE returns trueFalse', () {
      expect(BackendQuestionType.fromWire('TRUE_FALSE'), BackendQuestionType.trueFalse);
    });

    test('fromWire NUMBER returns number', () {
      expect(BackendQuestionType.fromWire('NUMBER'), BackendQuestionType.number);
    });

    test('fromWire NUMERIC alias returns number', () {
      expect(BackendQuestionType.fromWire('NUMERIC'), BackendQuestionType.number);
    });

    test('fromWire null defaults to text', () {
      expect(BackendQuestionType.fromWire(null), BackendQuestionType.text);
    });

    test('fromWire unknown defaults to text', () {
      expect(BackendQuestionType.fromWire('UNKNOWN'), BackendQuestionType.text);
    });

    test('fromWire is case-insensitive', () {
      expect(BackendQuestionType.fromWire('text'), BackendQuestionType.text);
      expect(BackendQuestionType.fromWire('yes_no'), BackendQuestionType.yesNo);
    });

    test('fromWire handles dashes', () {
      expect(BackendQuestionType.fromWire('YES-NO'), BackendQuestionType.yesNo);
    });

    test('toWire TEXT', () {
      expect(BackendQuestionType.text.toWire(), 'TEXT');
    });

    test('toWire YES_NO', () {
      expect(BackendQuestionType.yesNo.toWire(), 'YES_NO');
    });

    test('toWire TRUE_FALSE', () {
      expect(BackendQuestionType.trueFalse.toWire(), 'TRUE_FALSE');
    });

    test('toWire NUMBER', () {
      expect(BackendQuestionType.number.toWire(), 'NUMBER');
    });

    test('round-trip fromWire → toWire preserves value', () {
      for (final wire in ['TEXT', 'YES_NO', 'TRUE_FALSE', 'NUMBER']) {
        expect(BackendQuestionType.fromWire(wire).toWire(), wire);
      }
    });
  });

  // =========================================================================
  // BackendQuestionDto
  // =========================================================================

  group('BackendQuestionDto', () {
    test('fromJson parses all fields', () {
      final dto = BackendQuestionDto.fromJson({
        'id': 10,
        'prompt': 'How is your pain today?',
        'type': 'NUMBER',
        'required': true,
        'active': true,
        'ordinal': 0,
      });

      expect(dto.id, 10);
      expect(dto.prompt, 'How is your pain today?');
      expect(dto.type, BackendQuestionType.number);
      expect(dto.required, true);
      expect(dto.active, true);
      expect(dto.ordinal, 0);
    });

    test('fromJson defaults', () {
      final dto = BackendQuestionDto.fromJson({});

      expect(dto.id, isNull);
      expect(dto.prompt, '');
      expect(dto.type, BackendQuestionType.text);
      expect(dto.required, false);
      expect(dto.active, true);
      expect(dto.ordinal, 0);
    });

    test('toJson includes all fields', () {
      const dto = BackendQuestionDto(
        id: 5,
        prompt: 'Did you sleep well?',
        type: BackendQuestionType.yesNo,
        required: false,
        active: true,
        ordinal: 1,
      );

      final json = dto.toJson();
      expect(json['id'], 5);
      expect(json['prompt'], 'Did you sleep well?');
      expect(json['type'], 'YES_NO');
      expect(json['required'], false);
      expect(json['active'], true);
      expect(json['ordinal'], 1);
    });

    test('toJson omits null id', () {
      const dto = BackendQuestionDto(
        prompt: 'New question',
        type: BackendQuestionType.text,
        required: true,
        active: true,
        ordinal: 0,
      );
      expect(dto.toJson().containsKey('id'), false);
    });

    test('copyWith updates prompt', () {
      const original = BackendQuestionDto(
        id: 1,
        prompt: 'Original',
        type: BackendQuestionType.text,
        required: false,
        active: true,
        ordinal: 0,
      );

      final updated = original.copyWith(prompt: 'Updated');
      expect(updated.prompt, 'Updated');
      expect(updated.id, 1);
      expect(updated.type, BackendQuestionType.text);
    });

    test('copyWith preserves unchanged fields', () {
      const original = BackendQuestionDto(
        id: 5,
        prompt: 'Test',
        type: BackendQuestionType.number,
        required: true,
        active: false,
        ordinal: 3,
      );

      final copy = original.copyWith();
      expect(copy.id, 5);
      expect(copy.prompt, 'Test');
      expect(copy.type, BackendQuestionType.number);
      expect(copy.required, true);
      expect(copy.active, false);
      expect(copy.ordinal, 3);
    });
  });

  // =========================================================================
  // PostWithCommentCountDto
  // =========================================================================

  group('PostWithCommentCountDto', () {
    test('fromJson parses all fields', () {
      final dto = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 42,
        'content': 'Hello world',
        'imageUrl': 'https://example.com/img.jpg',
        'createdAt': '2026-03-17T10:00:00.000Z',
        'commentCount': 5,
        'username': 'alice',
      });

      expect(dto.id, 1);
      expect(dto.userId, 42);
      expect(dto.content, 'Hello world');
      expect(dto.imageUrl, 'https://example.com/img.jpg');
      expect(dto.createdAt.year, 2026);
      expect(dto.commentCount, 5);
      expect(dto.username, 'alice');
    });

    test('fromJson defaults username to Unknown User when null', () {
      final dto = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': 'Test',
        'createdAt': '2026-03-17T10:00:00.000Z',
        'commentCount': 0,
      });
      expect(dto.username, 'Unknown User');
    });

    test('imageUrl is optional', () {
      final dto = PostWithCommentCountDto(
        id: 1,
        userId: 1,
        content: 'No image',
        createdAt: DateTime.now(),
        commentCount: 0,
        username: 'bob',
      );
      expect(dto.imageUrl, isNull);
    });

    test('post with zero comments', () {
      final dto = PostWithCommentCountDto.fromJson({
        'id': 2,
        'userId': 5,
        'content': 'New post',
        'createdAt': '2026-03-17T10:00:00.000Z',
        'commentCount': 0,
        'username': 'charlie',
      });
      expect(dto.commentCount, 0);
    });
  });
}
