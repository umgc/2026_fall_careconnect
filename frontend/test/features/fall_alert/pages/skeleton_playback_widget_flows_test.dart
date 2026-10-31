// Tests for SkeletonPlaybackWidget and SkeletonPainter
// (lib/features/fall_alert/pages/skeleton_playback_widget.dart) using a
// synthetic binary skeleton file built in the test.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:care_connect_app/features/fall_alert/pages/skeleton_playback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a version-3 skeleton file with [frames], each a list of
/// (index, probability, x, y) tuples.
String _skeletonFile({
  int version = 3,
  int width = 320,
  int height = 240,
  required List<List<List<int>>> frames,
  int msDelta = 40,
}) {
  final builder = BytesBuilder();
  final header = ByteData(28)
    ..setInt32(0, version, Endian.little)
    ..setInt16(16, width, Endian.little)
    ..setInt16(18, height, Endian.little)
    ..setInt16(26, frames.length, Endian.little);
  builder.add(header.buffer.asUint8List());
  for (final parts in frames) {
    // msDelta (2) + pad (1) + numParts (1) + bbox/probs/pad (16).
    final frameHeader = ByteData(20)
      ..setInt16(0, msDelta, Endian.little)
      ..setInt8(3, parts.length);
    builder.add(frameHeader.buffer.asUint8List());
    for (final p in parts) {
      final part = ByteData(6)
        ..setInt8(0, p[0])
        ..setInt8(1, p[1])
        ..setInt16(2, p[2], Endian.little)
        ..setInt16(4, p[3], Endian.little);
      builder.add(part.buffer.asUint8List());
    }
  }
  return base64Encode(builder.toBytes());
}

/// A full body: every keypoint index 0..17 with distinct coordinates.
List<List<int>> _fullBody({int shift = 0}) => [
      for (var i = 0; i < 18; i++) [i, 100, 50 + i * 5 + shift, 40 + i * 7],
    ];

Map<String, dynamic> _response(String skeleton) => {
      'data': {
        'alert': {
          'skeleton_file': skeleton,
          'background_url': 'https://example.test/bg.png',
        },
      },
    };

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> response, {
  http.Response Function()? background,
}) async {
  final client = MockClient(
    (_) async => (background ?? () => http.Response('missing', 404))(),
  );
  await http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: SkeletonPlaybackWidget(sampleResponse: response),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }, () => client);
}

void main() {
  group('SkeletonPlaybackWidget', () {
    testWidgets('unsupported version shows error icon', (tester) async {
      await _pump(
        tester,
        _response(_skeletonFile(version: 2, frames: [_fullBody()])),
      );
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('zero frames shows error icon', (tester) async {
      await _pump(tester, _response(_skeletonFile(frames: [])));
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('valid file paints skeleton and advances frames',
        (tester) async {
      await _pump(
        tester,
        _response(
          _skeletonFile(
            frames: [
              _fullBody(),
              _fullBody(shift: 10),
              // A sparse frame exercises missing-joint branches.
              [
                [0, 50, 10, 10],
                [14, 50, 12, 8],
              ],
            ],
          ),
        ),
      );
      expect(find.byIcon(Icons.error), findsNothing);
      final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SkeletonPainter,
      );
      expect(paint, findsOneWidget);
      final first = (tester.widget<CustomPaint>(paint).painter!
              as SkeletonPainter)
          .currentFrame;

      // Run the ticker long enough to cycle through frames.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 500));
      final later =
          (tester.widget<CustomPaint>(paint).painter! as SkeletonPainter)
              .currentFrame;
      expect(identical(first, later), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('undecodable background image is ignored', (tester) async {
      await _pump(
        tester,
        _response(_skeletonFile(frames: [_fullBody()])),
        background: () => http.Response('not an image', 200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.error), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('SkeletonPainter', () {
    FrameData frame(List<List<int>> parts) => FrameData(
          durationMs: 40,
          points: {
            for (final p in parts)
              p[0]: KeyPoint(x: p[2], y: p[3], confidence: p[1] / 255.0),
          },
        );

    void paintOnce(SkeletonPainter painter) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(400, 300));
      recorder.endRecording().dispose();
    }

    test('paints a full frame without a background', () {
      paintOnce(
        SkeletonPainter(
          backgroundImage: null,
          currentFrame: frame(_fullBody()),
          originalSize: const Size(320, 240),
        ),
      );
    });

    test('paints an empty frame', () {
      paintOnce(
        SkeletonPainter(
          backgroundImage: null,
          currentFrame: FrameData(points: const {}, durationMs: 16),
          originalSize: const Size(320, 240),
        ),
      );
    });

    testWidgets('paints over a background image', (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 4),
      );
      paintOnce(
        SkeletonPainter(
          backgroundImage: image,
          currentFrame: frame(_fullBody()),
          originalSize: const Size(320, 240),
        ),
      );
    });

    test('shouldRepaint compares image, frame and size', () {
      final f = frame(_fullBody());
      final a = SkeletonPainter(
        backgroundImage: null,
        currentFrame: f,
        originalSize: const Size(1, 1),
      );
      expect(
        a.shouldRepaint(
          SkeletonPainter(
            backgroundImage: null,
            currentFrame: f,
            originalSize: const Size(1, 1),
          ),
        ),
        isFalse,
      );
      expect(
        a.shouldRepaint(
          SkeletonPainter(
            backgroundImage: null,
            currentFrame: f,
            originalSize: const Size(2, 1),
          ),
        ),
        isTrue,
      );
    });
  });
}
