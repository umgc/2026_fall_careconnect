// CC-12 Increment 2: saving the QR picture in a browser (a download). Test
// Plan §3.27: TC-EMG-452, 453 (Testing Lead, DEF-EMG-25). TC-EMG-304, the
// browser-only version of this test, is withdrawn.
//
// The saver hands the picture to file_picker's saveFile, which in a browser
// downloads it under the given name. These tests replace FilePicker.platform
// with a fake, so they run on the VM. The live download is TC-EMG-324.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:care_connect_app/features/emergency_passport/utils/qr_image_save_web.dart';

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  final saves = <({String? fileName, Uint8List? bytes})>[];
  Object? error;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (error != null) throw error!;
    saves.add((fileName: fileName, bytes: bytes));
    return null; // what the web implementation returns
  }
}

void main() {
  late _FakeFilePicker picker;

  setUp(() => FilePicker.platform = picker = _FakeFilePicker());

  test(
      'TC-EMG-452: the picture is saved once, under the given name, byte for '
      'byte, and the save reports true', () async {
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 255]);

    final ok = await saveQrImage(png, 'careconnect-emergency-qr.png');

    expect(ok, isTrue);
    expect(picker.saves, hasLength(1));
    expect(picker.saves.single.fileName, 'careconnect-emergency-qr.png');
    expect(picker.saves.single.bytes, png);
  });

  test('TC-EMG-453: a save that fails reports false instead of throwing',
      () async {
    picker.error = ArgumentError('The bytes are required');

    final ok = await saveQrImage(Uint8List(0), 'careconnect-emergency-qr.png');

    expect(ok, isFalse);
    expect(picker.saves, isEmpty);
  });
}
