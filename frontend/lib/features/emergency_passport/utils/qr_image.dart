import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'qr_image_save_stub.dart'
    if (dart.library.io) 'qr_image_save_io.dart'
    if (dart.library.html) 'qr_image_save_web.dart' as impl;

/// A phone-shaped picture (1080 x 1920) with the QR in the middle and a short
/// label, made to be set as a lock screen. White background so any phone
/// camera can read it.
Future<Uint8List> lockScreenQrPng(String data) async {
  const width = 1080.0;
  const height = 1920.0;
  const qrSize = 720.0;
  const quiet = 48.0; // White border scanners need around the code.

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);

  final top = (height - qrSize) / 2 + 120;
  final left = (width - qrSize) / 2;

  void label(String text, double y, double size, FontWeight weight, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: width - 120);
    tp.paint(canvas, Offset((width - tp.width) / 2, y));
  }

  label('EMERGENCY MEDICAL INFO', top - quiet - 150, 56, FontWeight.w800,
      const Color(0xFFB91C1C));
  label('Scan with any phone camera', top - quiet - 70, 40, FontWeight.w500,
      const Color(0xFF374151));

  canvas.save();
  canvas.translate(left, top);
  QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
  ).paint(canvas, const Size(qrSize, qrSize));
  canvas.restore();

  final image =
      await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Saves the picture: a download on the web, the share sheet ("Save Image")
/// on a phone. Returns false if it could not.
Future<bool> saveQrImage(Uint8List png, String fileName) =>
    impl.saveQrImage(png, fileName);
