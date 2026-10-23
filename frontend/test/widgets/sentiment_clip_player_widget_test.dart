import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:care_connect_app/widgets/sentiment_clip_player_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final Map<int, StreamController<VideoEvent>> streams =
      <int, StreamController<VideoEvent>>{};
  final Map<int, Duration> positions = <int, Duration>{};
  int nextPlayerId = 0;

  @override
  Future<int?> create(DataSource dataSource) async {
    return _createPlayer(dataSource);
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    return _createPlayer(options.dataSource);
  }

  Future<int> _createPlayer(DataSource dataSource) async {
    calls.add('create');
    final playerId = nextPlayerId++;
    final stream = StreamController<VideoEvent>();
    streams[playerId] = stream;
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(minutes: 5),
      ),
    );
    return playerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await streams.remove(playerId)?.close();
  }

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return streams[playerId]!.stream;
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return positions[playerId] ?? Duration.zero;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo:${position.inSeconds}');
    positions[playerId] = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => Texture(textureId: playerId);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Texture(textureId: options.playerId);
}

Future<void> _pumpPlayerReady(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
  });

  group('SentimentClipPlayerWidget', () {
    testWidgets('seeks to clip start after initialize', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SentimentClipPlayerWidget(
            playbackUrl: 'https://example.com/recording.mp4',
            clipStartSec: 42,
            clipEndSec: 102,
          ),
        ),
      );

      await _pumpPlayerReady(tester);

      expect(fakePlatform.calls, contains('seekTo:42'));
      expect(find.byType(Chewie), findsOneWidget);
    });

    testWidgets('pauses when playback passes clip end', (tester) async {
      VideoPlayerController? captured;

      await tester.pumpWidget(
        _wrap(
          SentimentClipPlayerWidget(
            playbackUrl: 'https://example.com/recording.mp4',
            clipStartSec: 10,
            clipEndSec: 20,
            controllerFactory: (uri) {
              captured = VideoPlayerController.networkUrl(uri);
              return captured!;
            },
          ),
        ),
      );

      await _pumpPlayerReady(tester);

      fakePlatform.calls.removeWhere((call) => call == 'pause');
      await captured!.seekTo(const Duration(seconds: 21));
      await tester.pump();

      expect(fakePlatform.calls, contains('pause'));
    });

    testWidgets('removes playback listener on unmount', (tester) async {
      VideoPlayerController? captured;

      await tester.pumpWidget(
        _wrap(
          SentimentClipPlayerWidget(
            playbackUrl: 'https://example.com/recording.mp4',
            clipStartSec: 10,
            clipEndSec: 20,
            controllerFactory: (uri) {
              captured = VideoPlayerController.networkUrl(uri);
              return captured!;
            },
          ),
        ),
      );

      await _pumpPlayerReady(tester);

      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pump();

      fakePlatform.calls.clear();
      await captured!.seekTo(const Duration(seconds: 21));
      await tester.pump();

      expect(fakePlatform.calls, isNot(contains('pause')));
    });

    testWidgets('seeks on clip window change without re-fetching URL', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SentimentClipPlayerWidget(
            playbackUrl: 'https://example.com/recording.mp4',
            clipStartSec: 10,
            clipEndSec: 25,
          ),
        ),
      );

      await _pumpPlayerReady(tester);
      fakePlatform.calls.clear();

      await tester.pumpWidget(
        _wrap(
          const SentimentClipPlayerWidget(
            playbackUrl: 'https://example.com/recording.mp4',
            clipStartSec: 42,
            clipEndSec: 57,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakePlatform.calls, isNot(contains('create')));
      expect(fakePlatform.calls, contains('seekTo:42'));
    });

    testWidgets('shows error when playback URL is empty', (tester) async {
      var errorCalled = false;

      await tester.pumpWidget(
        _wrap(
          SentimentClipPlayerWidget(
            playbackUrl: '   ',
            clipStartSec: 0,
            clipEndSec: 30,
            onError: () => errorCalled = true,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Missing playback URL'), findsOneWidget);
      expect(errorCalled, isTrue);
    });
  });
}
