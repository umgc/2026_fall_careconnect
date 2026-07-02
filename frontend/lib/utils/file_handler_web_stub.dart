// file_handler_web_stub.dart
import 'dart:typed_data';

import '../abstracts/file_handler.dart';

class WebFileHandler implements FileHandler {
  @override
  Future<void> downloadFile(
    String fileName,
    Uint8List bytes,
    String contentType,
  ) {
    throw UnsupportedError('Web file downloads require a web runtime');
  }

  @override
  Future<FileUploadResult> processPickedFile(
    String? path,
    String? fileName,
    Uint8List? bytes,
  ) {
    throw UnsupportedError('Web file processing requires a web runtime');
  }
}
