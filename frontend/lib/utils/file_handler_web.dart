// file_handler_web.dart
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'dart:io' as io;
import '../abstracts/file_handler.dart';

class WebFileHandler implements FileHandler {
  @override
  Future<void> downloadFile(String fileName, Uint8List bytes, String contentType) async {
    try {
      final jsArray = bytes.toJS;
      final blob = web.Blob(
        [jsArray].toJS,
        web.BlobPropertyBag(type: contentType),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = url;
      anchor.style.display = 'none';
      anchor.download = fileName;
      web.document.body!.appendChild(anchor);
      anchor.click();
      web.document.body!.removeChild(anchor);
      web.URL.revokeObjectURL(url);
    } catch (e) {
      throw Exception('Web download failed: $e');
    }
  }

  @override
  Future<FileUploadResult> processPickedFile(String? path, String? fileName, Uint8List? bytes) async {
    if (bytes == null || fileName == null) {
      throw Exception('Web file processing requires bytes and filename');
    }

    // Create temporary file for web
    final tempDir = io.Directory.systemTemp;
    final tempFile = io.File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(bytes);

    return FileUploadResult(
      filePath: tempFile.path,
      isTemporary: true,
    );
  }
}

FileHandler createPlatformFileHandler() => WebFileHandler();
