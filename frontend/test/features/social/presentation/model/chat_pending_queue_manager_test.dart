import 'package:care_connect_app/features/social/presentation/model/chat_pending_queue_manager.dart';
import 'package:care_connect_app/features/social/presentation/model/message_dto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatPendingQueueManager', () {
    late ChatPendingQueueManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      manager = ChatPendingQueueManager();
    });

    test('conversationKey is stable regardless of user order', () {
      final first = manager.conversationKey(currentUserId: 42, peerUserId: 9);
      final second = manager.conversationKey(currentUserId: 9, peerUserId: 42);

      expect(first, '9_42');
      expect(second, '9_42');
    });

    test('persistToCache and restoreFromCache round-trip messages', () {
      const key = '3_8';
      final pending = [
        MessageDto(
          id: -1,
          senderId: 3,
          receiverId: 8,
          content: 'hello pending',
          timestamp: DateTime.utc(2026, 1, 10, 10, 0),
        ),
      ];

      manager.persistToCache(key, pending);
      final restored = manager.restoreFromCache(key);

      expect(restored, hasLength(1));
      expect(restored.first.content, 'hello pending');
      expect(restored.first.id, -1);
    });

    test('persistToDisk and restoreFromDisk round-trip messages', () async {
      const key = '5_11';
      final pending = [
        MessageDto(
          id: -1001,
          senderId: 5,
          receiverId: 11,
          content: 'message with attachment',
          timestamp: DateTime.utc(2026, 2, 2, 12, 30),
          attachmentId: 99,
          attachmentName: 'photo.jpg',
          attachmentContentType: 'image/jpeg',
          attachmentSize: 2048,
        ),
      ];

      await manager.persistToDisk(key, pending);
      final restored = await manager.restoreFromDisk(key);

      expect(restored, hasLength(1));
      expect(restored.first.id, -1001);
      expect(restored.first.senderId, 5);
      expect(restored.first.receiverId, 11);
      expect(restored.first.content, 'message with attachment');
      expect(restored.first.attachmentId, 99);
      expect(restored.first.attachmentName, 'photo.jpg');
      expect(restored.first.attachmentContentType, 'image/jpeg');
      expect(restored.first.attachmentSize, 2048);
    });

    test('restoreFromDisk ignores invalid entries and clears empty payload',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('chat_pending_1_9', [
        'not-json',
        '{"id":"bad","senderId":1,"receiverId":9,"content":"x","timestamp":"invalid"}',
      ]);

      final restored = await manager.restoreFromDisk('1_9');

      expect(restored, isEmpty);
      expect(prefs.getStringList('chat_pending_1_9'), isNull);
    });
  });
}
