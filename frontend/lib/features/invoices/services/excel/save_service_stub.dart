// lib/features/invoices/services/save_service_stub.dart

import 'package:flutter/material.dart';

/// Default implementation that throws an error.
///
/// This file is used as a fallback by the conditional import
/// for platforms that are neither mobile (using dart:io) nor web (using package:web).
Future<void> saveAndOpenFile(
    List<int> bytes, String fileName, BuildContext context) async {
  // This code will run only on platforms that don't support file saving via the other two files.
  throw UnsupportedError('File saving is not supported on this platform.');
}
