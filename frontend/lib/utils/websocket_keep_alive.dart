import 'dart:async';
import 'dart:math' as math;

import 'package:care_connect_app/config/env_constant.dart';

/// Keeps a WebSocket client connected: reconnect backoff plus heartbeats.
///
/// In deployed environments sockets go through the API Gateway WebSocket API,
/// which closes a connection after 10 minutes without traffic and after 2 hours
/// regardless, and drops every connection when the backend redeploys. Clients
/// therefore send a heartbeat well inside the idle limit and reconnect (and
/// re-authenticate) whenever the socket closes.
class WebSocketKeepAlive {
  WebSocketKeepAlive({
    this.heartbeatInterval = const Duration(minutes: 5),
    this.maxReconnectDelay = const Duration(seconds: 30),
    bool? heartbeatEnabled,
  }) : heartbeatEnabled = heartbeatEnabled ?? isWebSocketGatewayEnabled();

  /// Message the backend recognises and drops without dispatching.
  static const String heartbeatMessage = '{"type":"heartbeat"}';

  final Duration heartbeatInterval;
  final Duration maxReconnectDelay;

  /// Local Spring sockets have no idle limit, so heartbeats are only sent
  /// through the API Gateway.
  final bool heartbeatEnabled;

  int _attempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  /// Reconnect attempts since the last successful connection.
  int get attempts => _attempts;

  /// Delay before the next attempt: 1s, 2s, 4s, … capped at
  /// [maxReconnectDelay]. Each call counts as one attempt.
  Duration nextReconnectDelay() {
    final seconds = math.min(
      1 << math.min(_attempts, 16),
      maxReconnectDelay.inSeconds,
    );
    _attempts++;
    return Duration(seconds: seconds);
  }

  /// Runs [reconnect] after the next backoff delay, replacing any pending one.
  void scheduleReconnect(void Function() reconnect) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(nextReconnectDelay(), reconnect);
  }

  /// Call once the socket is open and authenticated: resets the backoff and
  /// starts heartbeats through [send].
  void onConnected(void Function(String message) send) {
    _attempts = 0;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    if (heartbeatEnabled) {
      _heartbeatTimer = Timer.periodic(
        heartbeatInterval,
        (_) => send(heartbeatMessage),
      );
    }
  }

  /// Call when the socket closes: stops heartbeats (a pending reconnect stays).
  void onDisconnected() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Stops heartbeats and any pending reconnect, e.g. on logout or dispose.
  void stop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    onDisconnected();
    _attempts = 0;
  }
}
