import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adds keyboard access to the calendar package's otherwise unfocusable views.
class CalendarKeyboardScrollBehavior extends MaterialScrollBehavior {
  const CalendarKeyboardScrollBehavior({required this.label});

  final String label;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      _KeyboardScrollRegion(
        label: label,
        details: details,
        child: super.buildOverscrollIndicator(context, child, details),
      );
}

class _KeyboardScrollRegion extends StatefulWidget {
  const _KeyboardScrollRegion({
    required this.label,
    required this.details,
    required this.child,
  });

  final String label;
  final ScrollableDetails details;
  final Widget child;

  @override
  State<_KeyboardScrollRegion> createState() => _KeyboardScrollRegionState();
}

class _KeyboardScrollRegionState extends State<_KeyboardScrollRegion> {
  bool _focused = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final controller = widget.details.controller;
    if (controller == null ||
        !controller.hasClients ||
        controller.positions.length != 1) {
      return KeyEventResult.ignored;
    }
    final position = controller.position;
    final key = event.logicalKey;
    final vertical =
        axisDirectionToAxis(widget.details.direction) == Axis.vertical;
    final previous =
        vertical ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowLeft;
    final next =
        vertical ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowRight;
    final page =
        key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown;
    double target;
    if (key == LogicalKeyboardKey.home) {
      target = position.minScrollExtent;
    } else if (key == LogicalKeyboardKey.end) {
      target = position.maxScrollExtent;
    } else if (key == previous || key == next || page) {
      final forward = key == next || key == LogicalKeyboardKey.pageDown;
      final reverse = axisDirectionIsReversed(widget.details.direction);
      final step = controller is PageController
          ? position.viewportDimension * controller.viewportFraction
          : page
              ? position.viewportDimension * 0.8
              : 50.0;
      target = position.pixels + (forward != reverse ? step : -step);
    } else {
      return KeyEventResult.ignored;
    }
    controller.animateTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        debugLabel: 'Calendar scroll region',
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _onKeyEvent,
        child: Semantics(
          label: widget.label,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                width: 2,
                color: _focused
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      );
}
