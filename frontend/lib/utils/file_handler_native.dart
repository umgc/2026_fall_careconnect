// file_handler_native.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../abstracts/file_handler.dart';

class NativeFileHandler implements FileHandler {
  /// Android/iOS/Windows
  @override
  Future<void> downloadFile(String fileName, Uint8List bytes, String contentType) async {
    try {
      Directory? directory;

      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            throw Exception('Storage permission denied');
          }
        }

        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes);
    } catch (e) {
      throw Exception('Native download failed: $e');
    }
  }

  @override
  Future<FileUploadResult> processPickedFile(String? path, String? fileName, Uint8List? bytes) async {
    if (path == null) {
      throw Exception('Native file processing requires file path');
    }

    return FileUploadResult(
      filePath: path,
      isTemporary: false,
    );
  }
}

FileHandler createPlatformFileHandler() => NativeFileHandler();
