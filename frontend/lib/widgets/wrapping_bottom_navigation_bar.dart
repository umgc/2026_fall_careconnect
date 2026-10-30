import 'package:flutter/material.dart';

/// Keeps every navigation label visible when a single row no longer fits.
class WrappingBottomNavigationBar extends StatelessWidget {
  const WrappingBottomNavigationBar({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
    required this.selectedColor,
    required this.unselectedColor,
  });

  final List<String> labels;
  final List<Widget> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color selectedColor;
  final Color unselectedColor;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12);
    final scaler = MediaQuery.textScalerOf(context);
    double minimumWidth = 100;
    for (final label in labels) {
      for (final word in label.split(RegExp(r'\s+'))) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        if (painter.width + 24 > minimumWidth) {
          minimumWidth = painter.width + 24;
        }
        painter.dispose();
      }
    }
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35),
          child: SingleChildScrollView(
            child: LayoutBuilder(builder: (context, constraints) {
              final columns = (constraints.maxWidth / minimumWidth)
                  .floor()
                  .clamp(1, labels.length)
                  .toInt();
              return Wrap(
                children: List.generate(
                    labels.length,
                    (index) => SizedBox(
                          width: constraints.maxWidth / columns,
                          child: Semantics(
                            selected: index == selectedIndex,
                            child: TextButton(
                              onPressed: () => onSelected(index),
                              style: TextButton.styleFrom(
                                foregroundColor: index == selectedIndex
                                    ? selectedColor
                                    : unselectedColor,
                                textStyle: style,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    icons[index],
                                    const SizedBox(height: 4),
                                    Text(labels[index],
                                        textAlign: TextAlign.center,
                                        softWrap: true,
                                        overflow: TextOverflow.visible),
                                  ]),
                            ),
                          ),
                        )),
              );
            }),
          ),
        ),
      ),
    );
  }
}
