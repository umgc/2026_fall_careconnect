// lib/features/invoices/services/save_service_mobile.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves the file to a temporary directory and opens it on mobile devices.
Future<void> saveAndOpenFile(
    List<int> bytes, String fileName, BuildContext context) async {
  final Directory dir = await getTemporaryDirectory();

  final String filePath = '${dir.path}/$fileName';
  final file = File(filePath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  await OpenFilex.open(file.path);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Exported successfully to ${file.path}')),
  );
}
