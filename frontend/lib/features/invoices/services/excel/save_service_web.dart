// lib/features/invoices/services/save_service_web.dart

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Creates a download link using the 'package:web' API and triggers it to save the file.
Future<void> saveAndOpenFile(
    List<int> bytes, String fileName, BuildContext context) async {
  final uint8List = Uint8List.fromList(bytes);
  final jsUint8Array = uint8List.toJS;
  final blob = web.Blob([jsUint8Array].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Download started...')),
  );
}
