// Tests for miscellaneous models: AuditLogItem, SearchUserDto,
// ConversationPreviewDto (extended).
// Pure Dart model tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/audit/audit_log_models.dart';
import 'package:care_connect_app/features/social/presentation/model/search_user_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/conversation_preview_dto.dart';

void main() {
  // =========================================================================
  // AuditLogItem
  // =========================================================================

  group('AuditLogItem', () {
    test('fromJson parses all fields', () {
      final item = AuditLogItem.fromJson({
        'type': 'VISIT_CREATED',
        'summary': 'New visit scheduled for John Doe',
        'caregiverName': 'Jane Smith',
        'createdAt': '2026-03-17T10:00:00.000Z',
      });

      expect(item.type, 'VISIT_CREATED');
      expect(item.summary, 'New visit scheduled for John Doe');
      expect(item.caregiverName, 'Jane Smith');
      expect(item.createdAt.year, 2026);
    });

    test('fromJson defaults type to empty string when null', () {
      final item = AuditLogItem.fromJson({
        'type': null,
        'summary': 'Test',
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(item.type, '');
    });

    test('fromJson defaults summary to empty string when null', () {
      final item = AuditLogItem.fromJson({
        'summary': null,
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(item.summary, '');
    });

    test('fromJson defaults caregiverName to Unknown caregiver', () {
      final item = AuditLogItem.fromJson({
        'caregiverName': null,
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(item.caregiverName, 'Unknown caregiver');
    });

    test('constructor stores all fields', () {
      final item = AuditLogItem(
        type: 'VISIT_UPDATED',
        summary: 'Priority changed',
        caregiverName: 'Admin',
        createdAt: DateTime(2026, 3, 17),
      );
      expect(item.type, 'VISIT_UPDATED');
    });
  });

  // =========================================================================
  // SearchUserDto
  // =========================================================================

  group('SearchUserDto', () {
    test('fromJson parses all fields', () {
      final dto = SearchUserDto.fromJson({
        'id': 42,
        'name': 'Alice Smith',
        'email': 'alice@example.com',
      });
      expect(dto.id, 42);
      expect(dto.name, 'Alice Smith');
      expect(dto.email, 'alice@example.com');
    });

    test('constructor stores fields', () {
      final dto = SearchUserDto(id: 1, name: 'Test', email: 'test@test.com');
      expect(dto.id, 1);
    });
  });

  // =========================================================================
  // ConversationPreviewDto — extended tests
  // =========================================================================

  group('ConversationPreviewDto', () {
    test('fromJson parses all fields', () {
      final dto = ConversationPreviewDto.fromJson({
        'peerId': 42,
        'peerName': 'Alice',
        'peerRole': 'CAREGIVER',
        'content': 'Hello!',
        'timestamp': '2026-03-17T10:00:00.000Z',
        'hasUnread': true,
      });

      expect(dto.peerId, 42);
      expect(dto.peerName, 'Alice');
      expect(dto.peerRole, 'CAREGIVER');
      expect(dto.content, 'Hello!');
      expect(dto.hasUnread, true);
    });

    test('fromJson defaults peerName to peerEmail when name is null', () {
      final dto = ConversationPreviewDto.fromJson({
        'peerId': 1,
        'peerName': null,
        'peerEmail': 'alice@test.com',
        'content': '',
        'timestamp': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.peerName, 'alice@test.com');
    });

    test('fromJson defaults peerName to Unknown when both null', () {
      final dto = ConversationPreviewDto.fromJson({
        'peerId': 1,
        'content': '',
        'timestamp': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.peerName, 'Unknown');
    });

    test('fromJson defaults content to empty string', () {
      final dto = ConversationPreviewDto.fromJson({
        'peerId': 1,
        'timestamp': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.content, '');
    });

    test('fromJson defaults hasUnread to false', () {
      final dto = ConversationPreviewDto.fromJson({
        'peerId': 1,
        'timestamp': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.hasUnread, false);
    });

    test('relationshipLabel returns Caregiver for CAREGIVER role', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'CAREGIVER',
        content: '', timestamp: DateTime.now(),
      );
      expect(dto.relationshipLabel, 'Caregiver');
    });

    test('relationshipLabel returns Patient for PATIENT role', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'PATIENT',
        content: '', timestamp: DateTime.now(),
      );
      expect(dto.relationshipLabel, 'Patient');
    });

    test('relationshipLabel returns Family for FAMILY_LINK role', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'FAMILY_LINK',
        content: '', timestamp: DateTime.now(),
      );
      expect(dto.relationshipLabel, 'Family');
    });

    test('relationshipLabel returns Admin for ADMIN role', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'ADMIN',
        content: '', timestamp: DateTime.now(),
      );
      expect(dto.relationshipLabel, 'Admin');
    });

    test('relationshipLabel returns empty string for unknown role', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'UNKNOWN',
        content: '', timestamp: DateTime.now(),
      );
      expect(dto.relationshipLabel, '');
    });

    test('hasUnread defaults to false in constructor', () {
      final dto = ConversationPreviewDto(
        peerId: 1, peerName: 'Test', peerRole: 'PATIENT',
        content: 'Hi', timestamp: DateTime.now(),
      );
      expect(dto.hasUnread, false);
    });
  });
}
