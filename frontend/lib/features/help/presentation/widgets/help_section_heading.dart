import '../../../../l10n/app_localizations.dart';
import '../../models/help_section.dart';

/// The contents menu and rendered section share this heading source.
String? helpSectionHeading(HelpSection section, AppLocalizations t) =>
    section.heading ??
    switch (section) {
      HelpTroubleshooting() => t.helpTroubleshooting,
      HelpRelatedArticles() => t.helpRelatedArticles,
      _ => null,
    };
