import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Future<void> exportAdminAnalyticsCsv(
  String csv,
  String fileName,
  BuildContext context,
) async {
  final bytes = utf8.encode(csv);
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('CSV download started')),
  );
}
