import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class BBox {
  final double l, t, w, h;
  const BBox(
      {required this.l, required this.t, required this.w, required this.h});
  factory BBox.from(Map<dynamic, dynamic> m) => BBox(
      l: (m['l'] as num).toDouble(),
      t: (m['t'] as num).toDouble(),
      w: (m['w'] as num).toDouble(),
      h: (m['h'] as num).toDouble());
}

class OcrLine {
  final String text;
  final BBox box;
  OcrLine({required this.text, required this.box});
  factory OcrLine.from(Map<dynamic, dynamic> m) =>
      OcrLine(text: m['text'] as String? ?? '', box: BBox.from(m['box']));
}

class OcrQr {
  final String value;
  final BBox? box;
  OcrQr({required this.value, this.box});
  factory OcrQr.from(Map<dynamic, dynamic> m) => OcrQr(
        value: m['value'] as String? ?? '',
        box: m['box'] == null ? null : BBox.from(m['box']),
      );
}

class OcrRichResult {
  final String path;
  final String text;
  final List<OcrLine> lines;
  final List<OcrQr> qrcodes;
  OcrRichResult(
      {required this.path,
      required this.text,
      required this.lines,
      required this.qrcodes});
  factory OcrRichResult.from(Map<dynamic, dynamic> m) => OcrRichResult(
        path: m['path'] as String,
        text: m['text'] as String? ?? '',
        lines: ((m['lines'] as List?) ?? const [])
            .map((e) => OcrLine.from(e))
            .toList(),
        qrcodes: ((m['qrcodes'] as List?) ?? const [])
            .map((e) => OcrQr.from(e))
            .toList(),
      );
}

class OcrService {
  static const _ch = MethodChannel('care_connect/ocr');

  static Future<List<OcrRichResult>> analyzeImages(List<XFile> images,
      {String? languageHint = "en-US"}) async {
    final paths = images.map((x) => x.path).toList();
    final res = await _ch.invokeMethod<List<dynamic>>(
        'analyze', {'paths': paths, 'languageHint': languageHint});
    final list = (res ?? const []);
    return list
        .cast<Map<dynamic, dynamic>>()
        .map((m) => OcrRichResult.from(m))
        .toList();
  }
}
