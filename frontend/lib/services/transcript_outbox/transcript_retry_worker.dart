import 'dart:async';
import 'dart:math';

import 'encrypted_transcript_outbox.dart';
import 'transcript_upload.dart';

class TranscriptRetryWorker {
  TranscriptRetryWorker({
    required TranscriptOutbox outbox,
    required TranscriptSegmentUploader uploader,
    required String jwtToken,
    Stream<bool>? connectivityChanges,
    DateTime Function()? clock,
    double Function()? randomDouble,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
  })  : _outbox = outbox,
        _uploader = uploader,
        _jwtToken = jwtToken,
        _clock = clock ?? DateTime.now,
        _randomDouble = randomDouble ?? Random.secure().nextDouble {
    _connectivitySubscription = connectivityChanges?.listen((isOnline) {
      if (isOnline) unawaited(wake());
    });
  }

  final TranscriptOutbox _outbox;
  final TranscriptSegmentUploader _uploader;
  final DateTime Function() _clock;
  final double Function() _randomDouble;
  final Duration baseDelay;
  final Duration maxDelay;

  String _jwtToken;
  bool _authPaused = false;
  bool _disposed = false;
  Future<void>? _activeRun;
  Timer? _timer;
  StreamSubscription<bool>? _connectivitySubscription;

  bool get isAuthPaused => _authPaused;

  Future<void> updateAuth(String jwtToken) async {
    _jwtToken = jwtToken;
    _authPaused = jwtToken.trim().isEmpty;
    if (!_authPaused) {
      await wake();
    }
  }

  Future<void> wake({bool force = false}) async {
    if (_disposed || _authPaused || _jwtToken.trim().isEmpty) return;
    final active = _activeRun;
    if (active != null) {
      await active;
      if (force) await wake(force: true);
      return;
    }
    final run = _drain(force: force);
    _activeRun = run;
    try {
      await run;
    } finally {
      if (identical(_activeRun, run)) _activeRun = null;
    }
  }

  Future<void> _drain({required bool force}) async {
    _timer?.cancel();
    _timer = null;
    final now = _clock().toUtc();
    final segments = await _outbox.all();
    segments.sort((a, b) {
      final due = a.nextAttemptAt.compareTo(b.nextAttemptAt);
      return due != 0 ? due : a.createdAt.compareTo(b.createdAt);
    });

    for (final segment in segments) {
      if (!force && segment.nextAttemptAt.isAfter(now)) break;
      final outcome = await _uploader.upload(segment, _jwtToken);
      switch (outcome) {
        case TranscriptUploadSucceeded():
        case TranscriptUploadTerminal():
          await _outbox.remove(segment.clientSegmentId);
        case TranscriptUploadAuthPaused():
          _authPaused = true;
          return;
        case TranscriptUploadRetryable(:final retryAfter):
          final delay = retryAfter ?? _backoffFor(segment.attemptCount);
          await _outbox.update(segment.scheduleRetry(now.add(delay)));
      }
    }
    await _scheduleNext();
  }

  Duration _backoffFor(int attemptCount) {
    final exponent = min(attemptCount, 16);
    final uncappedMs = baseDelay.inMilliseconds * pow(2, exponent);
    final cappedMs = min(uncappedMs.round(), maxDelay.inMilliseconds);
    final jitteredMs = (cappedMs * (0.5 + _randomDouble())).round();
    return Duration(milliseconds: min(jitteredMs, maxDelay.inMilliseconds));
  }

  Future<void> _scheduleNext() async {
    if (_disposed || _authPaused) return;
    final segments = await _outbox.all();
    if (segments.isEmpty) return;
    final next = segments
        .map((segment) => segment.nextAttemptAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(_clock().toUtc());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(wake());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _connectivitySubscription?.cancel();
    final active = _activeRun;
    if (active != null) await active;
  }
}
