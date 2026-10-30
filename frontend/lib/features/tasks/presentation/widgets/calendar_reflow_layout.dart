import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lets the calendar page grow vertically instead of squeezing its month grid.
class CalendarReflowLayout extends StatelessWidget {
  const CalendarReflowLayout(
      {super.key, required this.children, required this.isMonth});

  final List<Widget> children;
  final bool isMonth;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final reflow = constraints.maxWidth < 600 ||
            constraints.maxHeight < 700 ||
            scaler.scale(14) > 21;
        if (!reflow) return Column(children: children);
        final cellHeight = math.max(
            constraints.maxWidth / 7 / 1.5, scaler.scale(12) * 1.4 + 28);
        final calendarHeight = isMonth
            ? cellHeight * 6 + 72 + scaler.scale(14) * 1.5
            : math.max(400.0, constraints.maxHeight * 0.8);
        return SingleChildScrollView(
          key: const ValueKey('calendar-page-scroll'),
          child: Column(children: [
            for (final child in children)
              if (child is Expanded)
                SizedBox(height: calendarHeight, child: child.child)
              else
                child,
          ]),
        );
      });
}

/// Stacks the filter card and Today button when their labels need more room.
class CalendarFilterLayout extends StatelessWidget {
  const CalendarFilterLayout({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(14) <= 21) {
          return Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children)
              if (child is Flexible)
                child.child
              else
                Align(alignment: Alignment.centerRight, child: child)
          ],
        );
      });
}
