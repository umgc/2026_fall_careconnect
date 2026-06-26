import '../abstracts/file_handler.dart';
import '../utils/file_handler_stub.dart'
    if (dart.library.io) '../utils/file_handler_native.dart'
    if (dart.library.js_interop) '../utils/file_handler_web.dart';

class FileHandlerFactory {
  static FileHandler create() => createPlatformFileHandler();
}
