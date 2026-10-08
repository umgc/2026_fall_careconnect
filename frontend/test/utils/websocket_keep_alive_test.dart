// Tests for WebSocketKeepAlive (lib/utils/websocket_keep_alive.dart).
//
// Reconnect backoff and heartbeats are timer-driven, so timer behaviour runs
// inside testWidgets, whose fake clock lets `tester.pump(duration)` advance
// time instantly. No sockets are opened: the reconnect and send callbacks are
// plain closures that record calls.

import 'package:care_connect_app/utils/websocket_keep_alive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextReconnectDelay', () {
    test('doubles from 1s and caps at maxReconnectDelay', () {
      final keepAlive = WebSocketKeepAlive(
        maxReconnectDelay: const Duration(seconds: 10),
        heartbeatEnabled: false,
      );

      final delays = List.generate(6, (_) => keepAlive.nextReconnectDelay());

      expect(delays.map((d) => d.inSeconds), [1, 2, 4, 8, 10, 10]);
      expect(keepAlive.attempts, 6);
    });

    test('does not overflow after many attempts', () {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);

      for (var i = 0; i < 100; i++) {
        keepAlive.nextReconnectDelay();
      }

      expect(keepAlive.nextReconnectDelay(), const Duration(seconds: 30));
    });

    test('defaults heartbeats from the build (off without a gateway URL)', () {
      expect(WebSocketKeepAlive().heartbeatEnabled, isFalse);
    });
  });

  group('scheduleReconnect', () {
    testWidgets('runs the reconnect after the backoff delay', (tester) async {
      // Arrange
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);
      var reconnects = 0;

      // Act
      keepAlive.scheduleReconnect(() => reconnects++);
      await tester.pump(const Duration(milliseconds: 999));
      final beforeDelay = reconnects;
      await tester.pump(const Duration(milliseconds: 1));

      // Assert: nothing at 999ms, one reconnect at the 1s mark
      expect(beforeDelay, 0);
      expect(reconnects, 1);
      keepAlive.stop();
    });

    testWidgets('a newer schedule replaces a pending one', (tester) async {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);
      var first = 0;
      var second = 0;

      keepAlive.scheduleReconnect(() => first++);
      keepAlive.scheduleReconnect(() => second++);
      await tester.pump(const Duration(seconds: 5));

      expect(first, 0);
      expect(second, 1);
      keepAlive.stop();
    });

    testWidgets('stop cancels a pending reconnect and resets the backoff', (
      tester,
    ) async {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);
      var reconnects = 0;

      keepAlive.scheduleReconnect(() => reconnects++);
      keepAlive.stop();
      await tester.pump(const Duration(seconds: 5));

      expect(reconnects, 0);
      expect(keepAlive.attempts, 0);
    });
  });

  group('heartbeats', () {
    testWidgets('onConnected sends a heartbeat every interval', (tester) async {
      // Arrange: the production interval, safely inside API Gateway's 10 min
      // idle limit
      final keepAlive = WebSocketKeepAlive(
        heartbeatInterval: const Duration(minutes: 5),
        heartbeatEnabled: true,
      );
      final sent = <String>[];

      // Act
      keepAlive.onConnected(sent.add);
      await tester.pump(const Duration(minutes: 11));

      // Assert: two full intervals elapsed
      expect(sent, [
        WebSocketKeepAlive.heartbeatMessage,
        WebSocketKeepAlive.heartbeatMessage,
      ]);
      keepAlive.stop();
    });

    testWidgets('onConnected resets the backoff', (tester) async {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);
      keepAlive.nextReconnectDelay();
      keepAlive.nextReconnectDelay();

      keepAlive.onConnected((_) {});

      expect(keepAlive.attempts, 0);
      expect(keepAlive.nextReconnectDelay(), const Duration(seconds: 1));
    });

    testWidgets('no heartbeats when disabled (local sockets)', (tester) async {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: false);
      final sent = <String>[];

      keepAlive.onConnected(sent.add);
      await tester.pump(const Duration(minutes: 30));

      expect(sent, isEmpty);
    });

    testWidgets('onDisconnected stops heartbeats', (tester) async {
      final keepAlive = WebSocketKeepAlive(heartbeatEnabled: true);
      final sent = <String>[];

      keepAlive.onConnected(sent.add);
      keepAlive.onDisconnected();
      await tester.pump(const Duration(minutes: 30));

      expect(sent, isEmpty);
    });

    test('heartbeat message is the type the backend drops', () {
      expect(WebSocketKeepAlive.heartbeatMessage, '{"type":"heartbeat"}');
    });
  });
}
