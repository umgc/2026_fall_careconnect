import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';
import 'common_drawer.dart';
import 'responsive_container.dart';

/// A wrapper widget that applies responsive layout to any page
/// This ensures consistent responsive behavior across the entire application
class ResponsivePageWrapper extends StatelessWidget {
  final Widget child;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool centerContent;
  final bool applyPadding;
  final Color? backgroundColor;
  final PreferredSizeWidget? customAppBar;

  const ResponsivePageWrapper({
    super.key,
    required this.child,
    this.title = '',
    this.actions,
    this.floatingActionButton,
    this.drawer,
    this.centerContent = true,
    this.applyPadding = true,
    this.backgroundColor,
    this.customAppBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: customAppBar,
      drawer: drawer,
      body: _buildResponsiveBody(context),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildResponsiveBody(BuildContext context) {
    final deviceType = ResponsiveUtils.getDeviceType(context);
    final isLargeScreen = deviceType == DeviceType.desktop ||
        deviceType == DeviceType.largeDesktop;

    Widget contentWidget = child;

    // Apply padding if requested
    if (applyPadding) {
      contentWidget = Padding(
        padding: ResponsiveUtils.getPagePadding(context),
        child: contentWidget,
      );
    }

    // Use the ResponsiveContainer for consistent content width constraints
    return ResponsiveContainer(
      centerContent: centerContent,
      maxWidth: isLargeScreen ? ResponsiveUtils.maxContentWidth : null,
      child: contentWidget,
    );
  }
}

/// A responsive scaffold that can be used directly
class ResponsiveScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions; // Standard actions for the AppBar
  final List<Widget>? appBarActions; // Alias for actions to match previous code
  final Widget? body;
  final Widget? floatingActionButton;
  final String? currentRoute; // To set the current route for the drawer
  final bool centerContent;
  final bool applyPadding;
  final Color? backgroundColor;
  final PreferredSizeWidget? customAppBar;

  const ResponsiveScaffold({
    super.key,
    this.title = '',
    this.actions,
    this.appBarActions, // Allow both actions and appBarActions for flexibility
    this.body,
    this.floatingActionButton,
    this.currentRoute,
    this.centerContent = true,
    this.applyPadding = true,
    this.backgroundColor,
    this.customAppBar,
  });

  @override
  Widget build(BuildContext context) {
    // Create the app bar with title and actions
    final appBar = customAppBar ??
        AppBar(title: Text(title), actions: appBarActions ?? actions);

    // Create the drawer with the current route
    final drawer =
        currentRoute != null ? CommonDrawer(currentRoute: currentRoute!) : null;

    return ResponsivePageWrapper(
      title: title,
      actions: appBarActions ?? actions,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      centerContent: centerContent,
      applyPadding: applyPadding,
      backgroundColor: backgroundColor,
      customAppBar: appBar,
      child: body ?? Container(),
    );
  }
}
