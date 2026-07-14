// Tests for messaging and social DTOs.
// Covers MessageDto, FriendDto, FriendRequestDto, CommentDto.
// Pure Dart model tests — no HTTP, no widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/social/presentation/model/message_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_request_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/comment_dto.dart';

void main() {
  // =========================================================================
  // MessageDto
  // =========================================================================

  group('MessageDto', () {
    test('fromJson parses all required fields', () {
      final json = {
        'id': 42,
        'senderId': 1,
        'receiverId': 10,
        'content': 'Hello!',
        'timestamp': '2026-03-17T10:30:00.000Z',
      };
      final msg = MessageDto.fromJson(json);

      expect(msg.id, 42);
      expect(msg.senderId, 1);
      expect(msg.receiverId, 10);
      expect(msg.content, 'Hello!');
      expect(msg.timestamp.year, 2026);
    });

    test('fromJson handles null content with empty string default', () {
      final json = {
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': null,
        'timestamp': '2026-03-17T10:00:00.000Z',
      };
      expect(MessageDto.fromJson(json).content, '');
    });

    test('fromJson parses attachment fields', () {
      final json = {
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': 'See attached',
        'timestamp': '2026-03-17T10:00:00.000Z',
        'attachmentId': 99,
        'attachmentName': 'report.pdf',
        'attachmentContentType': 'application/pdf',
        'attachmentSize': 1024,
      };
      final msg = MessageDto.fromJson(json);

      expect(msg.attachmentId, 99);
      expect(msg.attachmentName, 'report.pdf');
      expect(msg.attachmentContentType, 'application/pdf');
      expect(msg.attachmentSize, 1024);
    });

    test('hasAttachment returns true when attachmentId is set', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(), attachmentId: 5,
      );
      expect(msg.hasAttachment, true);
    });

    test('hasAttachment returns false when attachmentId is null', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(),
      );
      expect(msg.hasAttachment, false);
    });

    test('isImage returns true for image content type', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(),
        attachmentContentType: 'image/jpeg',
      );
      expect(msg.isImage, true);
      expect(msg.isAudio, false);
    });

    test('isAudio returns true for audio content type', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(),
        attachmentContentType: 'audio/mpeg',
      );
      expect(msg.isAudio, true);
      expect(msg.isImage, false);
    });

    test('isImage and isAudio false for non-media type', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(),
        attachmentContentType: 'application/pdf',
      );
      expect(msg.isImage, false);
      expect(msg.isAudio, false);
    });

    test('isImage and isAudio false when contentType is null', () {
      final msg = MessageDto(
        id: 1, senderId: 1, receiverId: 2, content: '',
        timestamp: DateTime.now(),
      );
      expect(msg.isImage, false);
      expect(msg.isAudio, false);
    });

    test('queuedOffline defaults to false', () {
      final json = {
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': 'test',
        'timestamp': '2026-03-17T10:00:00.000Z',
      };
      expect(MessageDto.fromJson(json).queuedOffline, false);
    });

    test('queuedOffline true when set in JSON', () {
      final json = {
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': 'queued',
        'timestamp': '2026-03-17T10:00:00.000Z',
        'queuedOffline': true,
      };
      expect(MessageDto.fromJson(json).queuedOffline, true);
    });
  });

  // =========================================================================
  // FriendDto
  // =========================================================================

  group('FriendDto', () {
    test('fromJson parses all fields', () {
      final dto = FriendDto.fromJson({
        'id': 5,
        'name': 'Jane Doe',
        'email': 'jane@example.com',
      });
      expect(dto.id, 5);
      expect(dto.name, 'Jane Doe');
      expect(dto.email, 'jane@example.com');
    });

    test('constructor stores fields', () {
      final dto = FriendDto(id: 1, name: 'Test', email: 'test@test.com');
      expect(dto.id, 1);
      expect(dto.name, 'Test');
    });
  });

  // =========================================================================
  // FriendRequestDto
  // =========================================================================

  group('FriendRequestDto', () {
    test('fromJson parses all fields', () {
      final dto = FriendRequestDto.fromJson({
        'id': 10,
        'fromUserId': 1,
        'toUserId': 2,
        'from_username': 'alice',
      });
      expect(dto.id, 10);
      expect(dto.fromUserId, 1);
      expect(dto.toUserId, 2);
      expect(dto.fromUsername, 'alice');
    });

    test('constructor stores fields', () {
      final dto = FriendRequestDto(
        id: 1, fromUserId: 5, toUserId: 10, fromUsername: 'bob',
      );
      expect(dto.fromUsername, 'bob');
    });
  });

  // =========================================================================
  // CommentDto
  // =========================================================================

  group('CommentDto', () {
    test('fromJson parses all fields', () {
      final dto = CommentDto.fromJson({
        'id': 1,
        'userId': 42,
        'postId': 100,
        'content': 'Great post!',
        'username': 'alice',
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.id, 1);
      expect(dto.userId, 42);
      expect(dto.postId, 100);
      expect(dto.content, 'Great post!');
      expect(dto.username, 'alice');
      expect(dto.timestamp.year, 2026);
    });

    test('fromJson defaults username to Unknown User when null', () {
      final dto = CommentDto.fromJson({
        'id': 1,
        'userId': 1,
        'postId': 1,
        'content': 'Test',
        'username': null,
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.username, 'Unknown User');
    });

    test('fromJson defaults username when key absent', () {
      final dto = CommentDto.fromJson({
        'id': 1,
        'userId': 1,
        'postId': 1,
        'content': 'No username',
        'createdAt': '2026-03-17T10:00:00.000Z',
      });
      expect(dto.username, 'Unknown User');
    });

    test('constructor stores all fields', () {
      final dto = CommentDto(
        id: 5,
        userId: 10,
        postId: 20,
        content: 'Nice!',
        username: 'bob',
        timestamp: DateTime(2026, 3, 17),
      );
      expect(dto.id, 5);
      expect(dto.content, 'Nice!');
    });
  });
}
