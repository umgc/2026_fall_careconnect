import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/sentiment_clip_window.dart';

/// Inline 16:9 player for a ±15 s sentiment clip on the full composited MP4.
class SentimentClipPlayerWidget extends StatefulWidget {
  const SentimentClipPlayerWidget({
    super.key,
    required this.playbackUrl,
    required this.clipStartSec,
    required this.clipEndSec,
    this.onError,
    @visibleForTesting this.controllerFactory,
  });

  final String playbackUrl;
  final double clipStartSec;
  final double clipEndSec;
  final VoidCallback? onError;

  /// Test hook: build a controller without hitting the network.
  @visibleForTesting
  final VideoPlayerController Function(Uri url)? controllerFactory;

  @override
  State<SentimentClipPlayerWidget> createState() =>
      _SentimentClipPlayerWidgetState();
}

class _SentimentClipPlayerWidgetState extends State<SentimentClipPlayerWidget> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant SentimentClipPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackUrl != widget.playbackUrl) {
      _disposeControllers();
      _initializing = true;
      _error = null;
      _initPlayer();
      return;
    }
    if (oldWidget.clipStartSec != widget.clipStartSec ||
        oldWidget.clipEndSec != widget.clipEndSec) {
      unawaited(_seekToClipStart());
    }
  }

  Future<void> _initPlayer() async {
    final url = widget.playbackUrl.trim();
    if (url.isEmpty) {
      _setError('Missing playback URL');
      return;
    }

    final uri = Uri.parse(url);
    final controller = widget.controllerFactory?.call(uri) ??
        VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
    _videoController = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        return;
      }

      await _seekToClipStart();
      if (!mounted) {
        return;
      }

      controller.addListener(_onPlaybackTick);

      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: 16 / 9,
        allowFullScreen: false,
        showControls: true,
      );

      setState(() => _initializing = false);
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _seekToClipStart() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(sentimentClipSeekPosition(widget.clipStartSec));
    if (!mounted) {
      return;
    }
    await controller.play();
  }

  void _onPlaybackTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final endSec = effectiveSentimentClipEndSec(
      clipEndSec: widget.clipEndSec,
      videoDuration: controller.value.duration,
    );
    if (sentimentClipShouldPause(
      position: controller.value.position,
      clipEndSec: endSec,
    )) {
      controller.pause();
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _initializing = false;
    });
    widget.onError?.call();
  }

  void _disposeControllers() {
    _videoController?.removeListener(_onPlaybackTick);
    _chewieController?.dispose();
    final controller = _videoController;
    _chewieController = null;
    _videoController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Chewie(controller: _chewieController!),
    );
  }
}
