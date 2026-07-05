// file_handler_web.dart
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
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
    // Web has no local filesystem, so there is no real file path to return.
    // Callers on web must upload the picked bytes directly (e.g.
    // EnhancedFileService.uploadFileWeb). Touching dart:io here would break
    // web compilation, which is exactly what this handler must avoid.
    throw UnsupportedError(
      'processPickedFile is not supported on web; upload the picked bytes directly.',
    );
  }
}

// Platform-specific implementation for web platform
FileHandler createFileHandler() {
  return WebFileHandler();
}
