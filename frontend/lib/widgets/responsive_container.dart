import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';

/// A container that automatically adjusts its width based on screen size
/// to ensure content is displayed at a reasonable width on web and desktop
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool centerContent;
  final double? maxWidthPercentage;
  final double? maxWidth;
  final Color? backgroundColor;
  final BoxDecoration? decoration;

  /// Creates a container that automatically constrains its width on larger screens
  ///
  /// * [child] - The widget to display inside the container
  /// * [padding] - Optional padding to apply inside the container
  /// * [centerContent] - Whether to center the container horizontally on larger screens
  /// * [maxWidthPercentage] - Maximum width as a percentage of screen width (0.0 to 1.0)
  /// * [maxWidth] - Maximum width in logical pixels (overrides maxWidthPercentage if provided)
  /// * [backgroundColor] - Optional background color of the container
  /// * [decoration] - Optional decoration of the container (overrides backgroundColor)
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.centerContent = true,
    this.maxWidthPercentage,
    this.maxWidth,
    this.backgroundColor,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final deviceType = ResponsiveUtils.getDeviceType(context);
    final isLargeScreen = deviceType == DeviceType.desktop ||
        deviceType == DeviceType.largeDesktop;

    // Calculate the appropriate width constraint based on screen size
    final double calculatedMaxWidth;
    if (maxWidth != null) {
      calculatedMaxWidth = maxWidth!;
    } else if (maxWidthPercentage != null) {
      calculatedMaxWidth = screenWidth * maxWidthPercentage!;
    } else {
      // Default width constraints by device type
      calculatedMaxWidth = switch (deviceType) {
        DeviceType.mobile => screenWidth,
        DeviceType.tablet => screenWidth * 0.95,
        DeviceType.desktop => screenWidth * 0.85,
        DeviceType.largeDesktop => ResponsiveUtils.maxContentWidth,
      };
    }

    final Widget constrainedChild = Container(
      width: deviceType == DeviceType.mobile ? screenWidth : null,
      constraints: BoxConstraints(maxWidth: calculatedMaxWidth),
      padding: padding,
      decoration: decoration ??
          (backgroundColor != null
              ? BoxDecoration(color: backgroundColor)
              : null),
      child: child,
    );

    // Center the content on larger screens if requested
    if (centerContent && isLargeScreen) {
      return Center(child: constrainedChild);
    }

    return constrainedChild;
  }
}
