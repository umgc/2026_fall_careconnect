import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

class SkeletonPlaybackWidget extends StatefulWidget {
  final Map<String, dynamic> sampleResponse;

  const SkeletonPlaybackWidget({
    super.key,
    required this.sampleResponse,
  });

  @override
  State<SkeletonPlaybackWidget> createState() => _SkeletonPlaybackWidgetState();
}

class _SkeletonPlaybackWidgetState extends State<SkeletonPlaybackWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTimestamp = Duration.zero;

  List<FrameData> _frames = [];
  int _frameNum = 0;
  double _frameElapsed = 0;

  ui.Image? _backgroundImage;
  Size _originalAlertSize = Size.zero;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _parseAndLoadData();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_frames.isEmpty) return;

    if (_lastTimestamp == Duration.zero) {
      _lastTimestamp = elapsed;
      return;
    }

    final double dt =
        (elapsed.inMicroseconds - _lastTimestamp.inMicroseconds) / 1000.0;
    _lastTimestamp = elapsed;

    final double clampedDt = dt.clamp(0, 200.0);
    _frameElapsed += clampedDt;

    var cur = _frames[_frameNum];

    while (_frameElapsed >= cur.durationMs) {
      _frameElapsed -= cur.durationMs;
      _frameNum = (_frameNum + 1) % _frames.length;
      cur = _frames[_frameNum];
    }

    setState(() {});
  }

  Future<void> _parseAndLoadData() async {
    try {
      final String base64Data =
          widget.sampleResponse['data']['alert']['skeleton_file'];
      final String bgUrl =
          widget.sampleResponse['data']['alert']['background_url'];

      final Uint8List bytes = base64Decode(base64Data);
      final ByteData bd = bytes.buffer.asByteData();

      if (bd.getInt32(0, Endian.little) != 3) {
        debugPrint("Unsupported alert version");
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final int width = bd.getInt16(16, Endian.little);
      final int height = bd.getInt16(18, Endian.little);
      final int numFrames = bd.getInt16(26, Endian.little);

      if (numFrames <= 0) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      int cur = 28;
      final List<FrameData> loaded = [];
      for (int i = 0; i < numFrames; i++) {
        final int msDelta = bd.getInt16(cur, Endian.little);
        cur += 3;
        final int numParts = bd.getInt8(cur);
        cur += 1 + 8 + 8; // bbox + 7 probs + pad

        final Map<int, KeyPoint> framePoints = {};
        for (int j = 0; j < numParts; j++) {
          final int idx = bd.getInt8(cur);
          cur += 1;
          final int prob = bd.getInt8(cur);
          cur += 1;
          final int x = bd.getInt16(cur, Endian.little);
          cur += 2;
          final int y = bd.getInt16(cur, Endian.little);
          cur += 2;

          framePoints[idx] = KeyPoint(
            x: x,
            y: y,
            confidence: prob.clamp(0, 255) / 255.0,
          );
        }
        loaded.add(
            FrameData(points: framePoints, durationMs: math.max(16, msDelta)));
      }

      ui.Image? bg;
      try {
        final http.Response resp = await http.get(Uri.parse(bgUrl));

        // --- ADD THESE LINES ---
        debugPrint("Response Status Code: ${resp.statusCode}");
        debugPrint("Response Body: ${resp.body}");
        // ---------------------

        // If the status code is not 200, the rest will fail.
        if (resp.statusCode == 200) {
          final ui.Codec codec = await ui.instantiateImageCodec(resp.bodyBytes);
          final ui.FrameInfo fi = await codec.getNextFrame();
          bg = fi.image;
        } else {
          debugPrint("Failed to load image. Status code: ${resp.statusCode}");
        }
      } catch (e) {
        debugPrint("Background load error: $e");
      }
      // Match JS setInterval behavior with a uniform frame time
      final totalMs = loaded.fold<int>(0, (s, f) => s + f.durationMs);
      final uniform =
          (totalMs / math.max(1, loaded.length)).clamp(16, 200).round();
      final normalized = loaded
          .map((f) => FrameData(points: f.points, durationMs: uniform))
          .toList();

      setState(() {
        _frames = normalized; // do not reverse
        _backgroundImage = bg;
        _originalAlertSize = Size(width.toDouble(), height.toDouble());
        _isLoading = false;
      });

      _lastTimestamp = Duration.zero;
      _frameElapsed = 0;
      _frameNum = 0;
      _ticker.start();
    } catch (e) {
      debugPrint("Error loading playback data: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_frames.isEmpty) {
      return const Center(child: Icon(Icons.error, color: Colors.white));
    }

    return CustomPaint(
      painter: SkeletonPainter(
        backgroundImage: _backgroundImage,
        currentFrame: _frames[_frameNum],
        originalSize: _originalAlertSize,
      ),
      child: Container(),
    );
  }
}

class SkeletonPainter extends CustomPainter {
  final ui.Image? backgroundImage;
  final FrameData currentFrame;
  final Size originalSize;

  final Paint _paint = Paint();

  SkeletonPainter({
    required this.backgroundImage,
    required this.currentFrame,
    required this.originalSize,
  });

  // Color map that mirrors your HTML intent
  static const Map<String, Color> _col = {
    'white': Colors.white,
    'torsoFill': Color(0xFF7DB3FF),
    'shoulder': Color(0xFFF7B267),
    'rArm1': Color(0xFFFFD166),
    'rArm2': Color(0xFFFFE08A),
    'lArm1': Color(0xFFFF7F66),
    'lArm2': Color(0xFFFFA08A),
    'rHipChain': Color(0xFF4ECDC4),
    'rKnee': Color(0xFF58E0D8),
    'rAnkle': Color(0xFFA7FFF5),
    'lHipChain': Color(0xFFEF476F),
    'lKnee': Color(0xFFF26A8A),
    'lAnkle': Color(0xFFFF9BB1),
    'purple': Color(0xFF800080),
    'violet': Color(0xFF8A2BE2),
    'pink': Color(0xFFFFC0CB),
    'yellow': Colors.yellow,
    'lightYellow': Color(0xFFFFFFE0),
    'orange': Colors.orange,
    'darkSalmon': Color(0xFFE9967A),
    'salmon': Color(0xFFFA8072),
    'lightSalmon': Color(0xFFFFA07A),
    'darkTurquoise': Color(0xFF00CED1),
    'turquoise': Color(0xFF40E0D0),
    'paleTurquoise': Color(0xFFAFEEEE),
    'darkRed': Color(0xFF8B0000),
    'red': Colors.red,
  };

  static const List<Map<String, dynamic>> _pointPairs = [
    {'s': KP.HEAD, 'e': KP.NECK, 'c': 'pink'},
    {'s': KP.NECK, 'e': KP.R_SHOULDER, 'c': 'orange'},
    {'s': KP.R_SHOULDER, 'e': KP.R_ELBOW, 'c': 'yellow'},
    {'s': KP.R_ELBOW, 'e': KP.R_WRIST, 'c': 'lightYellow'},
    {'s': KP.NECK, 'e': KP.L_SHOULDER, 'c': 'darkSalmon'},
    {'s': KP.L_SHOULDER, 'e': KP.L_ELBOW, 'c': 'salmon'},
    {'s': KP.L_ELBOW, 'e': KP.L_WRIST, 'c': 'lightSalmon'},
    {'s': KP.NECK, 'e': KP.R_HIP, 'c': 'darkTurquoise'},
    {'s': KP.R_HIP, 'e': KP.R_KNEE, 'c': 'turquoise'},
    {'s': KP.R_KNEE, 'e': KP.R_ANKLE, 'c': 'paleTurquoise'},
    {'s': KP.NECK, 'e': KP.L_HIP, 'c': 'darkRed'},
    {'s': KP.L_HIP, 'e': KP.L_KNEE, 'c': 'red'},
    {'s': KP.L_KNEE, 'e': KP.L_ANKLE, 'c': 'orange'},
    {'s': KP.HEAD, 'e': KP.R_EYE, 'c': 'purple'},
    {'s': KP.R_EYE, 'e': KP.R_EAR, 'c': 'purple'},
    {'s': KP.HEAD, 'e': KP.L_EYE, 'c': 'violet'},
    {'s': KP.L_EYE, 'e': KP.L_EAR, 'c': 'violet'},
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // Mirror horizontally to match CSS transform: scaleX(-1)
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);

    // Background stretched to the full canvas
    if (backgroundImage != null) {
      final Rect src = Rect.fromLTWH(
        0,
        0,
        backgroundImage!.width.toDouble(),
        backgroundImage!.height.toDouble(),
      );
      final Rect dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(backgroundImage!, src, dst, _paint);
    } else {
      _paint.color = Colors.black;
      canvas.drawRect(Offset.zero & size, _paint);
    }

    final Map<int, KeyPoint> pts = currentFrame.points;
    if (pts.isEmpty) {
      canvas.restore();
      return;
    }

    // Fit original alert size inside current canvas
    final FittedSizes fs = applyBoxFit(BoxFit.contain, originalSize, size);
    final Rect outputRect =
        Alignment.center.inscribe(fs.destination, Offset.zero & size);
    final double scale = fs.destination.width / fs.source.width;
    final Offset offset = outputRect.topLeft;

    canvas.clipRect(outputRect);

    // Pull joints
    final H = _pt(pts, KP.HEAD, scale, offset);
    final N = _pt(pts, KP.NECK, scale, offset);
    final RS = _pt(pts, KP.R_SHOULDER, scale, offset);
    final RE = _pt(pts, KP.R_ELBOW, scale, offset);
    final RW = _pt(pts, KP.R_WRIST, scale, offset);
    final LS = _pt(pts, KP.L_SHOULDER, scale, offset);
    final LE = _pt(pts, KP.L_ELBOW, scale, offset);
    final LW = _pt(pts, KP.L_WRIST, scale, offset);
    final RH = _pt(pts, KP.R_HIP, scale, offset);
    final RK = _pt(pts, KP.R_KNEE, scale, offset);
    final RA = _pt(pts, KP.R_ANKLE, scale, offset);
    final LH = _pt(pts, KP.L_HIP, scale, offset);
    final LK = _pt(pts, KP.L_KNEE, scale, offset);
    final LA = _pt(pts, KP.L_ANKLE, scale, offset);
    final REYE = _pt(pts, KP.R_EYE, scale, offset);
    final LEYE = _pt(pts, KP.L_EYE, scale, offset);
    final REAR = _pt(pts, KP.R_EAR, scale, offset);
    final LEAR = _pt(pts, KP.L_EAR, scale, offset);

    const double W = 6.0;

    // Torso fill polygon
    _fillTorso(canvas, LS, RS, RH, LH, _col['torsoFill']!.withOpacity(0.25));

    // Spine and shoulders
    _strokeSeg(canvas, _paint, H, N, _col['white']!, W - 1);
    _strokeSeg(canvas, _paint, N, RS, _col['shoulder']!, W);
    _strokeSeg(canvas, _paint, N, LS, _col['shoulder']!, W);

    // Right arm
    _strokeSeg(canvas, _paint, RS, RE, _col['rArm1']!, W - 1);
    _strokeSeg(canvas, _paint, RE, RW, _col['rArm2']!, W - 1);

    // Left arm
    _strokeSeg(canvas, _paint, LS, LE, _col['lArm1']!, W - 1);
    _strokeSeg(canvas, _paint, LE, LW, _col['lArm2']!, W - 1);

    // Right leg
    _strokeSeg(canvas, _paint, N, RH, _col['rHipChain']!, W);
    _strokeSeg(canvas, _paint, RH, RK, _col['rKnee']!, W);
    _strokeSeg(canvas, _paint, RK, RA, _col['rAnkle']!, W);

    // Left leg
    _strokeSeg(canvas, _paint, N, LH, _col['lHipChain']!, W);
    _strokeSeg(canvas, _paint, LH, LK, _col['lKnee']!, W);
    _strokeSeg(canvas, _paint, LK, LA, _col['lAnkle']!, W);

    // Joint dots
    for (final p in [H, N, RS, RE, RW, LS, LE, LW, RH, RK, RA, LH, LK, LA]) {
      _dot(canvas, _paint, p, 3.5, _col['white']!);
    }

    // Head outline stroke sized by head to neck distance
    _drawHeadStroke(canvas, _paint, H, N, _col['white']!, 3.0);

    // Classic stick lines like pointPairs in JS
    for (final pair in _pointPairs) {
      final a = _pt(pts, pair['s'] as int, scale, offset);
      final b = _pt(pts, pair['e'] as int, scale, offset);
      if (a == null || b == null) continue;
      final name = pair['c'] as String;
      final color = _col[name] ?? _col['white']!;
      _strokeSeg(canvas, _paint, a, b, color, 5.0);
    }

    // Optional: draw eye to ear small helpers to fully mirror JS pairs
    _strokeSeg(canvas, _paint, REYE, REAR, _col['purple']!, 5.0);
    _strokeSeg(canvas, _paint, LEYE, LEAR, _col['violet']!, 5.0);

    canvas.restore();
  }

  _ScaledPoint? _pt(
      Map<int, KeyPoint> points, int idx, double scale, Offset offset) {
    final p = points[idx];
    if (p == null) return null;
    return _ScaledPoint(
      Offset(p.x * scale + offset.dx, p.y * scale + offset.dy),
      p.confidence,
    );
  }

  void _fillTorso(Canvas canvas, _ScaledPoint? ls, _ScaledPoint? rs,
      _ScaledPoint? rh, _ScaledPoint? lh, Color color) {
    if (ls == null || rs == null || rh == null || lh == null) return;
    final path = Path()
      ..moveTo(ls.offset.dx, ls.offset.dy)
      ..lineTo(rs.offset.dx, rs.offset.dy)
      ..lineTo(rh.offset.dx, rh.offset.dy)
      ..lineTo(lh.offset.dx, lh.offset.dy)
      ..close();
    final p = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(path, p);
  }

  void _strokeSeg(Canvas canvas, Paint paint, _ScaledPoint? a, _ScaledPoint? b,
      Color color, double width) {
    if (a == null || b == null) return;
    final double alpha = (0.5 * (a.confidence + b.confidence)).clamp(0.25, 1.0);
    paint
      ..color = color.withOpacity(alpha)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(a.offset, b.offset, paint);
  }

  void _dot(
      Canvas canvas, Paint paint, _ScaledPoint? p, double radius, Color color) {
    if (p == null) return;
    paint
      ..color = color.withOpacity(p.confidence.clamp(0.25, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p.offset, radius, paint);
  }

  void _drawHeadStroke(Canvas canvas, Paint paint, _ScaledPoint? head,
      _ScaledPoint? neck, Color color, double lineWidth) {
    if (head == null || neck == null) return;
    final dx = head.offset.dx - neck.offset.dx;
    final dy = head.offset.dy - neck.offset.dy;
    final r = math.max(6.0, math.sqrt(dx * dx + dy * dy) * 0.6);
    paint
      ..color = color.withOpacity(head.confidence.clamp(0.25, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(head.offset, r, paint);
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
    return oldDelegate.backgroundImage != backgroundImage ||
        oldDelegate.currentFrame != currentFrame ||
        oldDelegate.originalSize != originalSize;
  }
}

// Constants for keypoints
class KP {
  static const int HEAD = 0;
  static const int NECK = 1;
  static const int R_SHOULDER = 2;
  static const int R_ELBOW = 3;
  static const int R_WRIST = 4;
  static const int L_SHOULDER = 5;
  static const int L_ELBOW = 6;
  static const int L_WRIST = 7;
  static const int R_HIP = 8;
  static const int R_KNEE = 9;
  static const int R_ANKLE = 10;
  static const int L_HIP = 11;
  static const int L_KNEE = 12;
  static const int L_ANKLE = 13;
  static const int R_EYE = 14;
  static const int L_EYE = 15;
  static const int R_EAR = 16;
  static const int L_EAR = 17;
}

class KeyPoint {
  final int x, y;
  final double confidence;

  KeyPoint({required this.x, required this.y, required this.confidence});
}

class FrameData {
  final Map<int, KeyPoint> points;
  final int durationMs;

  FrameData({required this.points, required this.durationMs});
}

class _ScaledPoint {
  final Offset offset;
  final double confidence;

  _ScaledPoint(this.offset, this.confidence);
}
