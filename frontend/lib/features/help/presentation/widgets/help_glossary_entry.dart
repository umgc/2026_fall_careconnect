import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../models/help_glossary_term.dart';
import 'help_accessibility.dart';
import 'help_link_tile.dart';

/// A shared meaning using the app's typography and colors.
class HelpGlossaryEntry extends StatelessWidget {
  const HelpGlossaryEntry(
      {super.key,
      required this.term,
      this.selected = false,
      this.headingLevel = 2,
      this.headingFocusNode,
      this.onGlossarySelected,
      this.guides = const []});
  final HelpGlossaryTerm term;
  final bool selected;
  final int headingLevel;
  final FocusNode? headingFocusNode;
  final VoidCallback? onGlossarySelected;
  final List<Widget> guides;

  @override
  Widget build(BuildContext context) =>
      HelpAccessibility(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;
    return Card(
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Focus(
              skipTraversal: true,
              focusNode: headingFocusNode,
              child: Semantics(
                  key: ValueKey('help-glossary-heading-${term.id}'),
                  selected: selected ? true : null,
                  header: true,
                  headingLevel: headingLevel,
                  child: Text(term.term, style: theme.textTheme.titleLarge))),
          const SizedBox(height: 8),
          Text(term.definition, style: theme.textTheme.bodyLarge),
          if (onGlossarySelected != null)
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: onGlossarySelected,
                    child: Text(t.helpSeeInGlossary(term.term)))),
          if (guides.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              key: ValueKey('help-glossary-articles-${term.id}'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                    theme.colorScheme.primary.withValues(
                        alpha:
                            theme.brightness == Brightness.light ? 0.06 : 0.12),
                    theme.colorScheme.surface),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.menu_book_outlined,
                      color: theme.colorScheme.primary, semanticLabel: null),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    headingLevel: headingLevel + 1,
                    child: Text(t.helpArticlesAboutWord(term.term),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text(t.helpGlossaryArticlesDescription,
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 12),
                  Theme(
                    data: theme.copyWith(
                      cardTheme: theme.cardTheme.copyWith(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                              color: theme.colorScheme.primary, width: 1.5),
                        ),
                      ),
                      textTheme: theme.textTheme.copyWith(
                        titleMedium: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: guides),
                  ),
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// One button per search result, with the meaning visible before opening it.
class HelpGlossaryResultTile extends StatelessWidget {
  const HelpGlossaryResultTile(
      {super.key, required this.term, required this.onTap});
  final HelpGlossaryTerm term;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HelpLinkTile(
        title: term.term,
        summary: term.definition,
        hint: AppLocalizations.of(context)!.helpOpenWordHint,
        titleStyle: helpTheme(Theme.of(context)).textTheme.titleMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        onTap: onTap,
      );
}
