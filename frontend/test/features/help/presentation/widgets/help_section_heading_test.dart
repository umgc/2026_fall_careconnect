// Unit tests for lib/features/help/presentation/widgets/help_section_heading.dart.
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_section_heading.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations t = AppLocalizationsEn();

  test('an explicit heading always wins', () {
    expect(
        helpSectionHeading(
            const HelpParagraph(text: 'x', heading: 'Before you start'), t),
        'Before you start');
    expect(
        helpSectionHeading(
            HelpTroubleshooting(tips: const [], heading: 'If it fails'), t),
        'If it fails');
  });

  test('troubleshooting, related and glossary sections get default headings',
      () {
    expect(helpSectionHeading(HelpTroubleshooting(tips: const []), t),
        'Troubleshooting');
    expect(helpSectionHeading(HelpRelatedArticles(articleIds: const []), t),
        'Related articles');
    expect(helpSectionHeading(HelpGlossaryTerms(termIds: const []), t),
        'Words in this article');
  });

  test('paragraphs and steps have no heading unless given one', () {
    expect(helpSectionHeading(const HelpParagraph(text: 'x'), t), isNull);
    expect(helpSectionHeading(HelpSteps(steps: const ['a']), t), isNull);
  });
}
