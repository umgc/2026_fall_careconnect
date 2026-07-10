import 'dart:typed_data';
import '../abstracts/file_handler.dart';

FileHandler createPlatformFileHandler() {
  throw UnsupportedError(
    'Cannot create a FileHandler without dart:io or dart:js_interop',
  );
}
