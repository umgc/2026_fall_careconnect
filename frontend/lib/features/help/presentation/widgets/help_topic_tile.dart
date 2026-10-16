import 'package:flutter/material.dart';

import '../../models/help_category.dart';
import '../../../../l10n/app_localizations.dart';
import 'help_link_tile.dart';

/// Topic navigation with one accessible title/description/button node.
class HelpTopicTile extends StatelessWidget {
  const HelpTopicTile(
      {super.key, required this.category, required this.onTap, this.focusNode});

  final HelpCategory category;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => MergeSemantics(
          child: Card(
        child: HelpLinkTile(
          title: category.title,
          summary: category.description,
          hint: AppLocalizations.of(context)!.helpOpenTopicHint,
          onTap: onTap,
          focusNode: focusNode,
        ),
      ));
}
