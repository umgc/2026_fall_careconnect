import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../../features/help/help_routes.dart';

/// Preserve user text scaling in Help, including nonlinear platform scaling.
/// Other screens retain their existing scaling policy.
class AppTextScaling extends StatefulWidget {
  const AppTextScaling({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  State<AppTextScaling> createState() => _AppTextScalingState();
}

// The delegate reports every push, pop and go. The route information value
// does not: Back updates it without notifying, and a push leaves it at the
// page underneath, so read the top-most route from the delegate instead.
class _AppTextScalingState extends State<AppTextScaling> {
  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_routeChanged);
  }

  @override
  void didUpdateWidget(AppTextScaling oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_routeChanged);
      widget.router.routerDelegate.addListener(_routeChanged);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_routeChanged);
    super.dispose();
  }

  // The Router below can report a route while it is building.
  void _routeChanged() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = widget.router;
    final media = MediaQuery.of(context);
    final path = router.routerDelegate.currentConfiguration.isEmpty
        ? router.routeInformationProvider.value.uri.path
        : router.state.uri.path;
    final isHelp =
        path == HelpRoutes.home || path.startsWith('${HelpRoutes.home}/');
    return MediaQuery(
        data: media.copyWith(
            textScaler: isHelp
                ? media.textScaler
                : TextScaler.linear(
                    (media.textScaler.scale(16) / 16).clamp(0.8, 1.2))),
        child: widget.child);
  }
}
