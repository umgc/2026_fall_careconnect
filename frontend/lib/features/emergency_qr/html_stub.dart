// Stub implementation for dart:html when running on non-web platforms

class Window {
  void open(String url, String target) {
    throw UnsupportedError(
        'HTML operations are only supported on web platforms');
  }
}

class Blob {
  Blob(List<dynamic> data);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) {
    throw UnsupportedError(
        'HTML operations are only supported on web platforms');
  }

  static void revokeObjectUrl(String url) {
    throw UnsupportedError(
        'HTML operations are only supported on web platforms');
  }
}

class AnchorElement {
  AnchorElement({String? href});

  void setAttribute(String name, String value) {
    throw UnsupportedError(
        'HTML operations are only supported on web platforms');
  }

  void click() {
    throw UnsupportedError(
        'HTML operations are only supported on web platforms');
  }
}

final window = Window();
