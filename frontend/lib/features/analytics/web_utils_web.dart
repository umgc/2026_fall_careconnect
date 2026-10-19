import 'package:web/web.dart' as web;
import 'dart:typed_data';
import 'dart:js_interop';

// Web-specific utilities for file downloads
void downloadFile(String fileName, dynamic bytes, [String? contentType]) {
  final Uint8List data;
  if (bytes is Uint8List) {
    data = bytes;
  } else if (bytes is List<int>) {
    data = Uint8List.fromList(bytes);
  } else {
    throw ArgumentError('Unsupported bytes type: ${bytes.runtimeType}');
  }

  // Convert Uint8List to JSUint8Array and create blob
  final jsArray = data.toJS;
  final blob = web.Blob(
    [jsArray].toJS,
    contentType != null
        ? web.BlobPropertyBag(type: contentType)
        : web.BlobPropertyBag(),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;

  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}
