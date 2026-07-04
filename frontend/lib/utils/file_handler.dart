// file_handler.dart
//
// Platform-aware entry point for file handling. Selects the native
// implementation by default and the web implementation only when
// `dart:html` is available, so `package:web` / `dart:js_interop` are never
// pulled into a mobile/desktop build.
export 'file_handler_native.dart'
    if (dart.library.html) 'file_handler_web.dart';
