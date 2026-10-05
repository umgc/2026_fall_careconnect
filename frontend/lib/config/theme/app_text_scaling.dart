import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/help/help_routes.dart';

/// Preserve user text scaling in Help, including nonlinear platform scaling.
/// Other screens retain their existing scaling policy.
class AppTextScaling extends StatelessWidget {
  const AppTextScaling({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<RouteInformation>(
        valueListenable: router.routeInformationProvider,
        builder: (context, route, _) {
          final media = MediaQuery.of(context);
          final path = route.uri.path;
          final isHelp =
              path == HelpRoutes.home || path.startsWith('${HelpRoutes.home}/');
          return MediaQuery(
              data: media.copyWith(
                  textScaler: isHelp
                      ? media.textScaler
                      : TextScaler.linear(
                          (media.textScaler.scale(16) / 16).clamp(0.8, 1.2))),
              child: child);
        },
      );
}
