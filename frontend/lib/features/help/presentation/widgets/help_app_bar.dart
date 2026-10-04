import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import 'help_navigation_bar.dart';

/// Keeps Help shortcuts in the header, wrapping for narrow or enlarged text.
AppBar helpAppBar(BuildContext context, {required String title}) {
  final t = AppLocalizations.of(context)!;
  final width = MediaQuery.sizeOf(context).width - 24;
  final style = Theme.of(context).textTheme.titleMedium!;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final sizes = [t.helpCenterHome, t.helpBackToSettings].map((label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: math.max(1, width - 64));
    // Button padding, icon, and icon/label gap add 64 horizontal pixels.
    final size = Size(painter.width + 64, math.max(48, painter.height + 24));
    painter.dispose();
    return size;
  }).toList();
  final singleRow = sizes[0].width + sizes[1].width + 12 <= width;
  final height = 24.0 +
      (singleRow
          ? math.max(sizes[0].height, sizes[1].height)
          : sizes[0].height + sizes[1].height + 8);

  return AppBar(
    title: Text(title),
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: const HelpNavigationBar(),
    ),
  );
}
