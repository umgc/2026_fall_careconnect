import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportAdminAnalyticsCsv(
  String csv,
  String fileName,
  BuildContext context,
) async {
  final tempDir = await getTemporaryDirectory();
  final path = '${tempDir.path}/$fileName';
  await File(path).writeAsBytes(utf8.encode(csv), flush: true);

  await Share.shareXFiles(
    [XFile(path, mimeType: 'text/csv', name: fileName)],
    subject: 'Product Analytics Export',
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('CSV export ready to share or save')),
  );
}
