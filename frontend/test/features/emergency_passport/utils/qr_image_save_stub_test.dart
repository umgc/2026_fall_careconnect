// CC-12 Increment 2: platforms that can't save a picture. Test Plan §3.27:
// TC-EMG-280 (the pull request's).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/emergency_passport/utils/qr_image_save_stub.dart';

void main() {
  test('TC-EMG-280: says it could not save, so the screen suggests a screenshot', () async {
    expect(await saveQrImage(Uint8List(4), 'x.png'), isFalse);
  });
}
