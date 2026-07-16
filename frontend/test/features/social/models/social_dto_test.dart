// Tests for social DTOs:
//   CommentDto, ConversationPreviewDto, FriendDto, FriendRequestDto,
//   MessageDto, PostWithCommentCountDto, SearchUserDto.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/social/presentation/model/comment_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/conversation_preview_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_request_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/message_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/PostWithCommentCountDto.dart';
import 'package:care_connect_app/features/social/presentation/model/search_user_dto.dart';

void main() {
  group('CommentDto', () {
    test('constructor stores fields', () {
      final dt = DateTime(2025, 6, 1, 12, 0);
      final c = CommentDto(
        id: 1, userId: 10, postId: 20, content: 'Hello', username: 'alice', timestamp: dt,
      );
      expect(c.id, 1);
      expect(c.userId, 10);
      expect(c.postId, 20);
      expect(c.content, 'Hello');
      expect(c.username, 'alice');
      expect(c.timestamp, dt);
    });

    test('fromJson parses fields', () {
      final c = CommentDto.fromJson({
        'id': 5,
        'userId': 11,
        'postId': 22,
        'content': 'Nice post',
        'username': 'bob',
        'createdAt': '2025-07-04T09:00:00.000Z',
      });
      expect(c.id, 5);
      expect(c.username, 'bob');
      expect(c.content, 'Nice post');
    });

    test('fromJson defaults username to Unknown User when missing', () {
      final c = CommentDto.fromJson({
        'id': 6, 'userId': 1, 'postId': 2, 'content': 'x',
        'createdAt': '2025-01-01T00:00:00.000Z',
      });
      expect(c.username, 'Unknown User');
    });
  });

  group('ConversationPreviewDto', () {
    test('constructor stores fields', () {
      final dt = DateTime(2025, 8, 1);
      final cp = ConversationPreviewDto(
        peerId: 3, peerName: 'Carol', peerRole: 'CAREGIVER', content: 'Hey!', timestamp: dt,
      );
      expect(cp.peerId, 3);
      expect(cp.peerName, 'Carol');
      expect(cp.content, 'Hey!');
    });

    test('fromJson parses fields', () {
      final cp = ConversationPreviewDto.fromJson({
        'peerId': 7, 'peerName': 'Dave', 'content': 'Hi',
        'timestamp': '2025-09-15T10:30:00.000Z',
      });
      expect(cp.peerId, 7);
      expect(cp.peerName, 'Dave');
    });
  });

  group('FriendDto', () {
    test('constructor stores fields', () {
      final f = FriendDto(id: 100, name: 'Eve', email: 'eve@example.com');
      expect(f.id, 100);
      expect(f.name, 'Eve');
      expect(f.email, 'eve@example.com');
    });

    test('fromJson parses fields', () {
      final f = FriendDto.fromJson({'id': 200, 'name': 'Frank', 'email': 'frank@x.com'});
      expect(f.id, 200);
      expect(f.email, 'frank@x.com');
    });
  });

  group('FriendRequestDto', () {
    test('constructor stores fields', () {
      final fr = FriendRequestDto(
        id: 1, fromUserId: 10, toUserId: 20, fromUsername: 'grace',
      );
      expect(fr.id, 1);
      expect(fr.fromUserId, 10);
      expect(fr.toUserId, 20);
      expect(fr.fromUsername, 'grace');
    });

    test('fromJson parses from_username key', () {
      final fr = FriendRequestDto.fromJson({
        'id': 2, 'fromUserId': 30, 'toUserId': 40, 'from_username': 'henry',
      });
      expect(fr.fromUsername, 'henry');
    });
  });

  group('MessageDto', () {
    test('constructor stores fields', () {
      final dt = DateTime(2025, 10, 1, 8, 0);
      final m = MessageDto(
        id: 1, senderId: 5, receiverId: 6, content: 'Hello!', timestamp: dt,
      );
      expect(m.id, 1);
      expect(m.senderId, 5);
      expect(m.receiverId, 6);
      expect(m.content, 'Hello!');
    });

    test('fromJson parses fields', () {
      final m = MessageDto.fromJson({
        'id': 9, 'senderId': 11, 'receiverId': 12,
        'content': 'World', 'timestamp': '2025-11-01T00:00:00.000Z',
      });
      expect(m.content, 'World');
    });
  });

  group('PostWithCommentCountDto', () {
    test('constructor stores fields', () {
      final dt = DateTime(2025, 5, 5);
      final p = PostWithCommentCountDto(
        id: 1, userId: 2, content: 'My post', createdAt: dt,
        commentCount: 3, username: 'ivan',
      );
      expect(p.id, 1);
      expect(p.imageUrl, isNull);
      expect(p.commentCount, 3);
    });

    test('fromJson parses fields and defaults username', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 10, 'userId': 20, 'content': 'Post!',
        'createdAt': '2025-06-06T00:00:00.000Z',
        'commentCount': 5,
      });
      expect(p.username, 'Unknown User');
      expect(p.commentCount, 5);
    });

    test('fromJson includes imageUrl when present', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 11, 'userId': 21, 'content': 'Img post',
        'imageUrl': 'https://img.example.com/1.jpg',
        'createdAt': '2025-07-07T00:00:00.000Z',
        'commentCount': 0, 'username': 'judy',
      });
      expect(p.imageUrl, 'https://img.example.com/1.jpg');
    });
  });

  group('SearchUserDto', () {
    test('constructor stores fields', () {
      final s = SearchUserDto(id: 99, name: 'Karl', email: 'karl@test.com');
      expect(s.id, 99);
      expect(s.name, 'Karl');
      expect(s.email, 'karl@test.com');
    });

    test('fromJson parses fields', () {
      final s = SearchUserDto.fromJson({'id': 88, 'name': 'Laura', 'email': 'l@x.com'});
      expect(s.id, 88);
      expect(s.name, 'Laura');
    });
  });
}
