import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../models/help_glossary_term.dart';
import 'help_glossary_theme.dart';

/// A shared meaning using the app's typography and colors.
class HelpGlossaryEntry extends StatelessWidget {
  const HelpGlossaryEntry(
      {super.key,
      required this.term,
      this.selected = false,
      this.onGlossarySelected,
      this.guides = const []});
  final HelpGlossaryTerm term;
  final bool selected;
  final VoidCallback? onGlossarySelected;
  final List<Widget> guides;

  @override
  Widget build(BuildContext context) => Theme(
      data: helpGlossaryTheme(Theme.of(context)),
      child: Builder(builder: _buildContent));

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;
    return Semantics(
        selected: selected ? true : null,
        child: Card(
          shape: selected
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.primary, width: 2))
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                      header: true,
                      child:
                          Text(term.term, style: theme.textTheme.titleLarge)),
                  const SizedBox(height: 8),
                  Text(term.definition, style: theme.textTheme.bodyLarge),
                  if (onGlossarySelected != null)
                    Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                            style: TextButton.styleFrom(
                                minimumSize: const Size(0, 48)),
                            onPressed: onGlossarySelected,
                            child: Text(t.helpSeeInGlossary(term.term)))),
                  if (guides.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(t.helpRelatedArticles,
                        style: theme.textTheme.titleMedium),
                    ...guides,
                  ],
                ]),
          ),
        ));
  }
}

/// One button per search result, with the meaning visible before opening it.
class HelpGlossaryResultTile extends StatelessWidget {
  const HelpGlossaryResultTile(
      {super.key, required this.term, required this.onTap});
  final HelpGlossaryTerm term;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
            button: true,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              title: Text(term.term,
                  style: helpGlossaryTheme(Theme.of(context))
                      .textTheme
                      .titleMedium),
              subtitle: Text(term.definition,
                  style:
                      helpGlossaryTheme(Theme.of(context)).textTheme.bodyLarge),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap,
            )),
      );
}
