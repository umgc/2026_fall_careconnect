// file_handler.dart
import 'dart:typed_data';

abstract class FileHandler {
  Future<void> downloadFile(
      String fileName, Uint8List bytes, String contentType);
  Future<FileUploadResult> processPickedFile(
      String? path, String? fileName, Uint8List? bytes);
}

class FileUploadResult {
  final String filePath;
  final bool isTemporary;

  FileUploadResult({required this.filePath, required this.isTemporary});
}
