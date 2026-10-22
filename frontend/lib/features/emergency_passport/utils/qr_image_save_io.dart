import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the share sheet, where the patient picks "Save Image" (iOS) or
/// saves to Photos/Files (Android).
Future<bool> saveQrImage(Uint8List png, String fileName) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png', name: fileName)],
    ));
    return true;
  } catch (_) {
    return false;
  }
}
