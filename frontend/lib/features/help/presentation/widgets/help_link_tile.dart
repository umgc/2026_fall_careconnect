import 'package:flutter/material.dart';

/// One named button with a title, optional summary, and a visible focus border.
class HelpLinkTile extends StatefulWidget {
  const HelpLinkTile(
      {super.key,
      required this.title,
      this.summary,
      required this.hint,
      required this.onTap,
      this.focusNode,
      this.titleStyle,
      this.contentPadding});
  final String title;
  final String? summary;
  final String hint;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<HelpLinkTile> createState() => _HelpLinkTileState();
}

class _HelpLinkTileState extends State<HelpLinkTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: widget.hint,
        child: ListTile(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                  color:
                      _focused ? theme.colorScheme.primary : Colors.transparent,
                  width: 3)),
          minTileHeight: 48,
          contentPadding: widget.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(widget.title,
              style: widget.titleStyle ?? theme.textTheme.titleMedium),
          subtitle: widget.summary == null
              ? null
              : Text(widget.summary!, style: theme.textTheme.bodyLarge),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
