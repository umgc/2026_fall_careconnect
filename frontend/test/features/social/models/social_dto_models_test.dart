import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/social/presentation/model/comment_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/conversation_preview_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/friend_request_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/message_dto.dart';
import 'package:care_connect_app/features/social/presentation/model/PostWithCommentCountDto.dart';
import 'package:care_connect_app/features/social/presentation/model/search_user_dto.dart';

void main() {
  // ===== CommentDto =====
  group('CommentDto', () {
    test('constructor assigns all fields correctly', () {
      final dt = DateTime(2025, 6, 1, 12, 30, 45);
      final c = CommentDto(
        id: 1,
        userId: 10,
        postId: 20,
        content: 'Hello world',
        username: 'alice',
        timestamp: dt,
      );
      expect(c.id, 1);
      expect(c.userId, 10);
      expect(c.postId, 20);
      expect(c.content, 'Hello world');
      expect(c.username, 'alice');
      expect(c.timestamp, dt);
    });

    test('fromJson parses all fields from valid JSON', () {
      final c = CommentDto.fromJson({
        'id': 5,
        'userId': 11,
        'postId': 22,
        'content': 'Nice post',
        'username': 'bob',
        'createdAt': '2025-07-04T09:00:00.000Z',
      });
      expect(c.id, 5);
      expect(c.userId, 11);
      expect(c.postId, 22);
      expect(c.content, 'Nice post');
      expect(c.username, 'bob');
      expect(c.timestamp, DateTime.parse('2025-07-04T09:00:00.000Z'));
    });

    test('fromJson defaults username to Unknown User when null', () {
      final c = CommentDto.fromJson({
        'id': 6,
        'userId': 1,
        'postId': 2,
        'content': 'x',
        'username': null,
        'createdAt': '2025-01-01T00:00:00.000Z',
      });
      expect(c.username, 'Unknown User');
    });

    test('fromJson defaults username to Unknown User when key missing', () {
      final c = CommentDto.fromJson({
        'id': 6,
        'userId': 1,
        'postId': 2,
        'content': 'x',
        'createdAt': '2025-01-01T00:00:00.000Z',
      });
      expect(c.username, 'Unknown User');
    });

    test('constructor with empty string content', () {
      final c = CommentDto(
        id: 0,
        userId: 0,
        postId: 0,
        content: '',
        username: '',
        timestamp: DateTime(2020),
      );
      expect(c.content, '');
      expect(c.username, '');
      expect(c.id, 0);
    });

    test('fromJson with zero IDs', () {
      final c = CommentDto.fromJson({
        'id': 0,
        'userId': 0,
        'postId': 0,
        'content': '',
        'username': 'test',
        'createdAt': '2020-01-01T00:00:00.000Z',
      });
      expect(c.id, 0);
      expect(c.userId, 0);
      expect(c.postId, 0);
    });

    test('fromJson parses ISO date with timezone offset', () {
      final c = CommentDto.fromJson({
        'id': 1,
        'userId': 1,
        'postId': 1,
        'content': 'test',
        'username': 'u',
        'createdAt': '2025-12-31T23:59:59.999Z',
      });
      expect(c.timestamp.year, 2025);
      expect(c.timestamp.month, 12);
      expect(c.timestamp.day, 31);
    });

    test('fromJson with large IDs', () {
      final c = CommentDto.fromJson({
        'id': 999999999,
        'userId': 888888888,
        'postId': 777777777,
        'content': 'large ids',
        'username': 'biguser',
        'createdAt': '2025-01-01T00:00:00.000Z',
      });
      expect(c.id, 999999999);
      expect(c.userId, 888888888);
      expect(c.postId, 777777777);
    });

    test('fromJson with special characters in content', () {
      final c = CommentDto.fromJson({
        'id': 1,
        'userId': 1,
        'postId': 1,
        'content': 'Hello <b>world</b> & "quotes" \'apostrophe\'',
        'username': 'user@123',
        'createdAt': '2025-06-01T00:00:00.000Z',
      });
      expect(c.content, 'Hello <b>world</b> & "quotes" \'apostrophe\'');
      expect(c.username, 'user@123');
    });
  });

  // ===== ConversationPreviewDto =====
  group('ConversationPreviewDto', () {
    test('constructor assigns all fields correctly', () {
      final dt = DateTime(2025, 8, 1, 14, 0);
      final cp = ConversationPreviewDto(
        peerId: 3,
        peerName: 'Carol',
        peerRole: 'CAREGIVER',
        content: 'Hey!',
        timestamp: dt,
      );
      expect(cp.peerId, 3);
      expect(cp.peerName, 'Carol');
      expect(cp.peerRole, 'CAREGIVER');
      expect(cp.content, 'Hey!');
      expect(cp.timestamp, dt);
    });

    test('fromJson parses all fields from valid JSON', () {
      final cp = ConversationPreviewDto.fromJson({
        'peerId': 7,
        'peerName': 'Dave',
        'content': 'Hi there',
        'timestamp': '2025-09-15T10:30:00.000Z',
      });
      expect(cp.peerId, 7);
      expect(cp.peerName, 'Dave');
      expect(cp.content, 'Hi there');
      expect(cp.timestamp, DateTime.parse('2025-09-15T10:30:00.000Z'));
    });

    test('constructor with empty strings', () {
      final cp = ConversationPreviewDto(
        peerId: 0,
        peerName: '',
        peerRole: '',
        content: '',
        timestamp: DateTime(2020),
      );
      expect(cp.peerId, 0);
      expect(cp.peerName, '');
      expect(cp.content, '');
    });

    test('fromJson with zero peerId', () {
      final cp = ConversationPreviewDto.fromJson({
        'peerId': 0,
        'peerName': 'Nobody',
        'content': 'empty',
        'timestamp': '2020-01-01T00:00:00.000Z',
      });
      expect(cp.peerId, 0);
    });

    test('fromJson preserves long content', () {
      final longContent = 'A' * 10000;
      final cp = ConversationPreviewDto.fromJson({
        'peerId': 1,
        'peerName': 'Test',
        'content': longContent,
        'timestamp': '2025-01-01T00:00:00.000Z',
      });
      expect(cp.content.length, 10000);
    });

    test('fromJson with special characters in peerName', () {
      final cp = ConversationPreviewDto.fromJson({
        'peerId': 5,
        'peerName': "O'Brien-Smith",
        'content': 'Hello',
        'timestamp': '2025-03-01T00:00:00.000Z',
      });
      expect(cp.peerName, "O'Brien-Smith");
    });
  });

  // ===== FriendDto =====
  group('FriendDto', () {
    test('constructor assigns all fields correctly', () {
      final f = FriendDto(id: 100, name: 'Eve', email: 'eve@example.com');
      expect(f.id, 100);
      expect(f.name, 'Eve');
      expect(f.email, 'eve@example.com');
    });

    test('fromJson parses all fields from valid JSON', () {
      final f = FriendDto.fromJson({
        'id': 200,
        'name': 'Frank',
        'email': 'frank@x.com',
      });
      expect(f.id, 200);
      expect(f.name, 'Frank');
      expect(f.email, 'frank@x.com');
    });

    test('constructor with empty strings', () {
      final f = FriendDto(id: 0, name: '', email: '');
      expect(f.id, 0);
      expect(f.name, '');
      expect(f.email, '');
    });

    test('fromJson with zero id', () {
      final f = FriendDto.fromJson({
        'id': 0,
        'name': 'Zero',
        'email': 'zero@test.com',
      });
      expect(f.id, 0);
    });

    test('fromJson with large id', () {
      final f = FriendDto.fromJson({
        'id': 2147483647,
        'name': 'MaxInt',
        'email': 'max@int.com',
      });
      expect(f.id, 2147483647);
    });

    test('fromJson with email containing special characters', () {
      final f = FriendDto.fromJson({
        'id': 1,
        'name': 'Test User',
        'email': 'user+tag@sub.domain.com',
      });
      expect(f.email, 'user+tag@sub.domain.com');
    });

    test('fromJson with unicode name', () {
      final f = FriendDto.fromJson({
        'id': 42,
        'name': 'Jean-Pierre',
        'email': 'jp@test.com',
      });
      expect(f.name, 'Jean-Pierre');
    });
  });

  // ===== FriendRequestDto =====
  group('FriendRequestDto', () {
    test('constructor assigns all fields correctly', () {
      final fr = FriendRequestDto(
        id: 1,
        fromUserId: 10,
        toUserId: 20,
        fromUsername: 'grace',
      );
      expect(fr.id, 1);
      expect(fr.fromUserId, 10);
      expect(fr.toUserId, 20);
      expect(fr.fromUsername, 'grace');
    });

    test('fromJson parses from_username key (snake_case)', () {
      final fr = FriendRequestDto.fromJson({
        'id': 2,
        'fromUserId': 30,
        'toUserId': 40,
        'from_username': 'henry',
      });
      expect(fr.id, 2);
      expect(fr.fromUserId, 30);
      expect(fr.toUserId, 40);
      expect(fr.fromUsername, 'henry');
    });

    test('constructor with zero IDs', () {
      final fr = FriendRequestDto(
        id: 0,
        fromUserId: 0,
        toUserId: 0,
        fromUsername: '',
      );
      expect(fr.id, 0);
      expect(fr.fromUserId, 0);
      expect(fr.toUserId, 0);
      expect(fr.fromUsername, '');
    });

    test('fromJson with same fromUserId and toUserId', () {
      final fr = FriendRequestDto.fromJson({
        'id': 5,
        'fromUserId': 99,
        'toUserId': 99,
        'from_username': 'self',
      });
      expect(fr.fromUserId, fr.toUserId);
    });

    test('fromJson throws when from_username is null', () {
      expect(
        () => FriendRequestDto.fromJson({
          'id': 3,
          'fromUserId': 1,
          'toUserId': 2,
          'from_username': null,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('fromJson throws when from_username key is missing', () {
      expect(
        () => FriendRequestDto.fromJson({
          'id': 4,
          'fromUserId': 1,
          'toUserId': 2,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('fromJson with large IDs', () {
      final fr = FriendRequestDto.fromJson({
        'id': 999999,
        'fromUserId': 888888,
        'toUserId': 777777,
        'from_username': 'biguser',
      });
      expect(fr.id, 999999);
      expect(fr.fromUserId, 888888);
      expect(fr.toUserId, 777777);
    });
  });

  // ===== MessageDto =====
  group('MessageDto', () {
    test('constructor assigns all fields correctly', () {
      final dt = DateTime(2025, 10, 1, 8, 0);
      final m = MessageDto(
        id: 1,
        senderId: 5,
        receiverId: 6,
        content: 'Hello!',
        timestamp: dt,
      );
      expect(m.id, 1);
      expect(m.senderId, 5);
      expect(m.receiverId, 6);
      expect(m.content, 'Hello!');
      expect(m.timestamp, dt);
    });

    test('fromJson parses all fields from valid JSON', () {
      final m = MessageDto.fromJson({
        'id': 9,
        'senderId': 11,
        'receiverId': 12,
        'content': 'World',
        'timestamp': '2025-11-01T00:00:00.000Z',
      });
      expect(m.id, 9);
      expect(m.senderId, 11);
      expect(m.receiverId, 12);
      expect(m.content, 'World');
      expect(m.timestamp, DateTime.parse('2025-11-01T00:00:00.000Z'));
    });

    test('constructor with empty content', () {
      final m = MessageDto(
        id: 0,
        senderId: 0,
        receiverId: 0,
        content: '',
        timestamp: DateTime(2020),
      );
      expect(m.content, '');
      expect(m.id, 0);
    });

    test('fromJson with zero IDs', () {
      final m = MessageDto.fromJson({
        'id': 0,
        'senderId': 0,
        'receiverId': 0,
        'content': 'zero',
        'timestamp': '2020-01-01T00:00:00.000Z',
      });
      expect(m.id, 0);
      expect(m.senderId, 0);
      expect(m.receiverId, 0);
    });

    test('fromJson with same sender and receiver', () {
      final m = MessageDto.fromJson({
        'id': 1,
        'senderId': 42,
        'receiverId': 42,
        'content': 'self-message',
        'timestamp': '2025-01-01T00:00:00.000Z',
      });
      expect(m.senderId, m.receiverId);
    });

    test('fromJson preserves multiline content', () {
      final m = MessageDto.fromJson({
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': 'Line 1\nLine 2\nLine 3',
        'timestamp': '2025-06-01T00:00:00.000Z',
      });
      expect(m.content, 'Line 1\nLine 2\nLine 3');
    });

    test('fromJson with millisecond precision timestamp', () {
      final m = MessageDto.fromJson({
        'id': 1,
        'senderId': 1,
        'receiverId': 2,
        'content': 'precise',
        'timestamp': '2025-06-15T14:30:45.123Z',
      });
      expect(m.timestamp.millisecond, 123);
    });
  });

  // ===== PostWithCommentCountDto =====
  group('PostWithCommentCountDto', () {
    test('constructor assigns all required fields', () {
      final dt = DateTime(2025, 5, 5);
      final p = PostWithCommentCountDto(
        id: 1,
        userId: 2,
        content: 'My post',
        createdAt: dt,
        commentCount: 3,
        username: 'ivan',
      );
      expect(p.id, 1);
      expect(p.userId, 2);
      expect(p.content, 'My post');
      expect(p.createdAt, dt);
      expect(p.commentCount, 3);
      expect(p.username, 'ivan');
      expect(p.imageUrl, isNull);
    });

    test('constructor with imageUrl', () {
      final p = PostWithCommentCountDto(
        id: 1,
        userId: 2,
        content: 'post with image',
        imageUrl: 'https://example.com/img.jpg',
        createdAt: DateTime(2025),
        commentCount: 0,
        username: 'tester',
      );
      expect(p.imageUrl, 'https://example.com/img.jpg');
    });

    test('fromJson parses all fields with username provided', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 10,
        'userId': 20,
        'content': 'Post content',
        'imageUrl': 'https://img.example.com/pic.png',
        'createdAt': '2025-06-06T12:00:00.000Z',
        'commentCount': 5,
        'username': 'judy',
      });
      expect(p.id, 10);
      expect(p.userId, 20);
      expect(p.content, 'Post content');
      expect(p.imageUrl, 'https://img.example.com/pic.png');
      expect(p.createdAt, DateTime.parse('2025-06-06T12:00:00.000Z'));
      expect(p.commentCount, 5);
      expect(p.username, 'judy');
    });

    test('fromJson defaults username to Unknown User when missing', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 10,
        'userId': 20,
        'content': 'Post!',
        'createdAt': '2025-06-06T00:00:00.000Z',
        'commentCount': 5,
      });
      expect(p.username, 'Unknown User');
    });

    test('fromJson defaults username to Unknown User when null', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 10,
        'userId': 20,
        'content': 'Post!',
        'username': null,
        'createdAt': '2025-06-06T00:00:00.000Z',
        'commentCount': 5,
      });
      expect(p.username, 'Unknown User');
    });

    test('fromJson with null imageUrl', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': 'no image',
        'imageUrl': null,
        'createdAt': '2025-01-01T00:00:00.000Z',
        'commentCount': 0,
        'username': 'user',
      });
      expect(p.imageUrl, isNull);
    });

    test('fromJson with missing imageUrl key', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': 'no image key',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'commentCount': 0,
        'username': 'user',
      });
      expect(p.imageUrl, isNull);
    });

    test('fromJson with zero commentCount', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': 'no comments',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'commentCount': 0,
        'username': 'user',
      });
      expect(p.commentCount, 0);
    });

    test('fromJson with empty content', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': '',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'commentCount': 0,
        'username': 'user',
      });
      expect(p.content, '');
    });

    test('fromJson with large commentCount', () {
      final p = PostWithCommentCountDto.fromJson({
        'id': 1,
        'userId': 1,
        'content': 'popular',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'commentCount': 999999,
        'username': 'popular_user',
      });
      expect(p.commentCount, 999999);
    });

    test('constructor with null imageUrl explicitly', () {
      final p = PostWithCommentCountDto(
        id: 1,
        userId: 1,
        content: 'test',
        imageUrl: null,
        createdAt: DateTime(2025),
        commentCount: 0,
        username: 'u',
      );
      expect(p.imageUrl, isNull);
    });
  });

  // ===== SearchUserDto =====
  group('SearchUserDto', () {
    test('constructor assigns all fields correctly', () {
      final s = SearchUserDto(id: 99, name: 'Karl', email: 'karl@test.com');
      expect(s.id, 99);
      expect(s.name, 'Karl');
      expect(s.email, 'karl@test.com');
    });

    test('fromJson parses all fields from valid JSON', () {
      final s = SearchUserDto.fromJson({
        'id': 88,
        'name': 'Laura',
        'email': 'l@x.com',
      });
      expect(s.id, 88);
      expect(s.name, 'Laura');
      expect(s.email, 'l@x.com');
    });

    test('constructor with empty strings', () {
      final s = SearchUserDto(id: 0, name: '', email: '');
      expect(s.id, 0);
      expect(s.name, '');
      expect(s.email, '');
    });

    test('fromJson with zero id', () {
      final s = SearchUserDto.fromJson({
        'id': 0,
        'name': 'Zero',
        'email': 'zero@test.com',
      });
      expect(s.id, 0);
    });

    test('fromJson with complex email', () {
      final s = SearchUserDto.fromJson({
        'id': 1,
        'name': 'Complex',
        'email': 'user.name+tag@sub.domain.co.uk',
      });
      expect(s.email, 'user.name+tag@sub.domain.co.uk');
    });

    test('fromJson with name containing spaces', () {
      final s = SearchUserDto.fromJson({
        'id': 1,
        'name': 'John Doe Smith',
        'email': 'john@example.com',
      });
      expect(s.name, 'John Doe Smith');
    });

    test('fromJson with large id', () {
      final s = SearchUserDto.fromJson({
        'id': 2147483647,
        'name': 'MaxInt',
        'email': 'max@int.com',
      });
      expect(s.id, 2147483647);
    });
  });
}
