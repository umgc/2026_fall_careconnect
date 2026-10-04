/// Structured article content, independent of Flutter screen layout.
sealed class HelpSection {
  const HelpSection({this.heading});

  final String? heading;
}

final class HelpParagraph extends HelpSection {
  const HelpParagraph({required this.text, super.heading});

  final String text;
}

final class HelpSteps extends HelpSection {
  HelpSteps({required Iterable<String> steps, super.heading})
      : steps = List.unmodifiable(steps);

  final List<String> steps;
}

class HelpTroubleshootingTip {
  const HelpTroubleshootingTip({required this.problem, required this.solution});

  final String problem;
  final String solution;
}

final class HelpTroubleshooting extends HelpSection {
  HelpTroubleshooting(
      {required Iterable<HelpTroubleshootingTip> tips, super.heading})
      : tips = List.unmodifiable(tips);

  final List<HelpTroubleshootingTip> tips;
}

final class HelpRelatedArticles extends HelpSection {
  HelpRelatedArticles({required Iterable<String> articleIds, super.heading})
      : articleIds = List.unmodifiable(articleIds);

  final List<String> articleIds;
}
