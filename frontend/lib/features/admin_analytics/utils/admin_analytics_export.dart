import 'package:flutter/material.dart';

import 'admin_analytics_export_stub.dart'
    if (dart.library.io) 'admin_analytics_export_mobile.dart'
    if (dart.library.html) 'admin_analytics_export_web.dart' as impl;

Future<void> exportAdminAnalyticsCsv(
  String csv,
  String fileName,
  BuildContext context,
) {
  return impl.exportAdminAnalyticsCsv(csv, fileName, context);
}
