import 'package:care_connect_app/features/social/presentation/model/message_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageDto share cards', () {
    final ordinaryMessage = {
      'id': 1,
      'senderId': 2,
      'receiverId': 3,
      'content': 'Hello',
      'timestamp': '2026-10-24T14:02:11',
    };

    test('ordinary history messages keep nullable share fields', () {
      final message = MessageDto.fromJson(ordinaryMessage);

      expect(message.shareKind, isNull);
      expect(message.sharePatientId, isNull);
      expect(message.content, 'Hello');
    });

    test(
      'history parser accepts nullable fields and case-insensitive kinds',
      () {
        final message = MessageDto.fromJson({
          ...ordinaryMessage,
          'shareKind': 'mEdIcArE',
          'sharePatientId': 10,
        });

        expect(message.shareKind, ShareKind.medicare);
        expect(message.sharePatientId, 10);
        expect(message.shareKind!.wireValue, 'MEDICARE');
        expect(message.shareKind!.destinationTab, 'medicare');
      },
    );

    test(
      'live event parser maps message-received fields to the message DTO',
      () {
        final message = MessageDto.fromWebSocketEvent({
          'senderId': '2',
          'messageId': 55,
          'content': 'Shared my health information',
          'timestamp': '2026-10-24T14:02:11',
          'shareKind': 'HEALTH',
          'sharePatientId': 10,
        }, receiverId: 3);

        expect(message, isNotNull);
        expect(message!.senderId, 2);
        expect(message.receiverId, 3);
        expect(message.id, 55);
        expect(message.shareKind, ShareKind.health);
        expect(message.sharePatientId, 10);
      },
    );

    test(
      'live event with missing share metadata remains an ordinary message',
      () {
        final message = MessageDto.fromWebSocketEvent({
          'senderId': 2,
          'messageId': 55,
          'content': 'Hello',
          'timestamp': '2026-10-24T14:02:11',
          'shareKind': null,
          'sharePatientId': null,
        }, receiverId: 3);

        expect(message!.shareKind, isNull);
        expect(message.sharePatientId, isNull);
      },
    );
  });
}
