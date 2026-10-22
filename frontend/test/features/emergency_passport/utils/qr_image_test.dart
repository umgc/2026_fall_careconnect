// CC-12 Increment 2: the lock screen QR picture. Test Plan §3.27:
// TC-EMG-276, 277 (the pull request's), 302 (Testing Lead: the picture holds
// exactly the code for the link, with a scanner's white border).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:care_connect_app/features/emergency_passport/utils/qr_image.dart';

Future<(ByteData, int, int)> _pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (bytes, image.width, image.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'TC-EMG-276: makes a phone-shaped PNG (1080 x 1920) with the code drawn '
      'on it', () async {
    final png = await lockScreenQrPng('http://localhost:3000/#/passport/abc');

    // PNG signature.
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);

    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 1080);
    expect(image.height, 1920);

    // The middle of the QR area is not all white: the code is drawn.
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var dark = 0;
    for (var y = 700; y < 1300; y += 10) {
      for (var x = 200; x < 880; x += 10) {
        final i = (y * 1080 + x) * 4;
        if (bytes.getUint8(i) < 128) dark++;
      }
    }
    expect(dark, greaterThan(100));
  });

  test('TC-EMG-277: different codes give different pictures', () async {
    final a = await lockScreenQrPng('http://localhost:3000/#/passport/aaa');
    final b = await lockScreenQrPng('http://localhost:3000/#/passport/bbb');
    expect(a, isNot(equals(b)));
  });

  // ---------- Testing Lead ----------

  test(
      'TC-EMG-302: every module in the picture matches the QR code for the '
      'exact link (error correction M), so a camera reads the link and '
      'nothing else; the 48 px border around it is white and the title above '
      'it is red', () async {
    // A link the length the backend issues: base + /#/passport/ + 43 characters.
    const link = 'https://careconnect.example.org/#/passport/'
        'Q3k9xZ2vB7mN4pL8wR1tY6uE0aS5dF2gH9jK3lC7vB1';
    final (bytes, width, _) = await _pixels(await lockScreenQrPng(link));
    bool darkAt(double x, double y) =>
        bytes.getUint8((y.floor() * width + x.floor()) * 4) < 128;

    final qr = QrImage(QrCode.fromData(
        data: link, errorCorrectLevel: QrErrorCorrectLevel.M));
    final n = qr.moduleCount;
    // QrPainter's own layout: half-pixel modules, centred in 720 x 720 at
    // (180, 720).
    final px = ((720 / n) * 2).roundToDouble() / 2;
    final inset = (720 - px * n) / 2;
    final wrong = <String>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final x = 180 + inset + (c + 0.5) * px;
        final y = 720 + inset + (r + 0.5) * px;
        if (darkAt(x, y) != qr.isDark(r, c)) wrong.add('($r, $c)');
      }
    }
    expect(wrong, isEmpty, reason: '$n x $n modules');

    for (var d = 0.0; d <= 720; d += 4) {
      for (final p in [
        (180 - 24.0, 720 + d), // left border
        (900 + 24.0, 720 + d), // right border
        (180 + d, 720 - 24.0), // top border
        (180 + d, 1440 + 24.0), // bottom border
      ]) {
        expect(darkAt(p.$1, p.$2), isFalse, reason: 'border at $p');
      }
    }

    var red = 0;
    for (var y = 520; y < 600; y += 2) {
      for (var x = 100; x < 980; x += 4) {
        final i = (y * width + x) * 4;
        if (bytes.getUint8(i) > 150 &&
            bytes.getUint8(i + 1) < 80 &&
            bytes.getUint8(i + 2) < 80) {
          red++;
        }
      }
    }
    expect(red, greaterThan(50), reason: 'EMERGENCY MEDICAL INFO title');
  });
}
