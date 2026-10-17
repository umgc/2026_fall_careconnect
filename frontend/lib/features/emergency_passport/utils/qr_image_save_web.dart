import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Downloads the picture in the browser: file_picker's web saveFile clicks a
/// download link named [fileName] that is never added to the page, then
/// releases the picture. DEF-EMG-25: no dart:js_interop here, so the VM tests
/// can load this file and CI's coverage gate can measure it.
Future<bool> saveQrImage(Uint8List png, String fileName) async {
  try {
    await FilePicker.platform.saveFile(fileName: fileName, bytes: png);
    return true;
  } catch (_) {
    return false;
  }
}
