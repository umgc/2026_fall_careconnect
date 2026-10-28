import 'dart:ui' show Tristate;

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _contentsKey = ValueKey('help-article-contents');
const _toggleKey = ValueKey('help-contents-toggle');
const _toggleSemanticsKey = ValueKey('help-contents-toggle-semantics');
Finder _entry(int index) => find.byKey(ValueKey('help-contents-entry-$index'));
Finder _heading(int index) =>
    find.byKey(ValueKey('help-section-heading-$index'));

HelpRepository _catalog() => HelpRepository(
      categories: const [
        HelpCategory(id: 'guides', title: 'Guides', description: '')
      ],
      articles: [
        HelpArticle(
          id: 'long-guide',
          categoryId: 'guides',
          title: 'Long guide',
          summary: 'A guide with sections.',
          roles: [HelpRole.patient],
          sections: [
            HelpParagraph(
                heading: 'Overview',
                text: List.filled(40,
                        'Read these helpful instructions before continuing.')
                    .join(' ')),
            const HelpParagraph(heading: 'Details', text: 'First details.'),
            const HelpParagraph(heading: 'Details', text: 'Second details.'),
            HelpTroubleshooting(tips: const [
              HelpTroubleshootingTip(
                  problem: 'A problem', solution: 'A solution')
            ]),
            HelpRelatedArticles(articleIds: ['short-guide']),
          ],
        ),
        HelpArticle(
            id: 'short-guide',
            categoryId: 'guides',
            title: 'Short guide',
            summary: 'One section.',
            roles: [
              HelpRole.patient
            ],
            sections: const [
              HelpParagraph(heading: 'Only section', text: 'Short text.')
            ]),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  String articleId = 'long-guide',
  Brightness brightness = Brightness.light,
  TextScaler scaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  final catalog = _catalog();
  final router =
      GoRouter(initialLocation: HelpRoutes.article(articleId), routes: [
    GoRoute(
        path: HelpRoutes.home,
        builder: (_, __) => const Scaffold(),
        routes: [
          GoRoute(
              path: HelpRoutes.articlePattern,
              builder: (_, state) => HelpArticlePage(
                  articleId: state.pathParameters['articleId']!,
                  repository: catalog)),
        ]),
  ]);
  addTearDown(router.dispose);
  final theme =
      brightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme;
  await tester.pumpWidget(MaterialApp.router(
    theme:
        theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: scaler, disableAnimations: disableAnimations),
        child: child!),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapEntry(WidgetTester tester, int index) async {
  await tester.ensureVisible(_entry(index));
  await tester.pumpAndSettle();
  await tester.tap(_entry(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'TC-HELP-006: contents follow section order and collapse without hiding article text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester);
      final labels = tester
          .widgetList<Text>(find.descendant(
              of: find.byKey(_contentsKey), matching: find.byType(Text)))
          .map((text) => text.data);
      expect(labels, [
        'On this page',
        'Overview',
        'Details',
        'Details',
        'Troubleshooting',
        'Related articles'
      ]);
      for (var i = 0; i < 5; i++) {
        expect(
            tester
                .getSemantics(_entry(i))
                .getSemanticsData()
                .flagsCollection
                .isButton,
            isTrue);
      }
      expect(
          tester
              .getSemantics(find.byKey(_toggleSemanticsKey))
              .getSemanticsData()
              .flagsCollection
              .isExpanded,
          Tristate.isTrue);
      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(_entry(0), findsNothing);
      expect(
          tester
              .getSemantics(find.byKey(_toggleSemanticsKey))
              .getSemanticsData()
              .flagsCollection
              .isExpanded,
          Tristate.isFalse);
      expect(find.text('First details.'), findsOneWidget);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(_entry(4), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'TC-HELP-007: every contents entry targets its own heading, including repeated names',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester);
      for (var i = 0; i < 5; i++) {
        await _tapEntry(tester, i);
        expect(Focus.of(tester.element(_heading(i))).hasFocus, isTrue);
        expect(_heading(i).hitTestable(), findsOneWidget);
        expect(
            tester
                .getSemantics(_heading(i))
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue);
        expect(tester.getTopLeft(_heading(i)).dy,
            greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'TC-HELP-008: Tab and Enter jump to a heading; Back to top still returns to the beginning',
      (tester) async {
    await _pump(tester);
    // Back, header shortcuts, contents toggle, then the first section entry.
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pumpAndSettle();
    final label = find.descendant(of: _entry(0), matching: find.byType(Text));
    expect(Focus.of(tester.element(label)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(_heading(0))).hasFocus, isTrue);
    await _tapEntry(tester, 3);
    expect(find.text('Back to top').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Back to top'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('help-page-scroll')))
            .controller!
            .offset,
        0);
    expect(find.text('Back to top'), findsNothing);
  });

  testWidgets('TC-HELP-009: section jump respects disabled animations', (tester) async {
    await _pump(tester, disableAnimations: true);
    await tester.ensureVisible(_entry(2));
    await tester.pumpAndSettle();
    await tester.tap(_entry(2));
    await tester.pump();
    expect(Focus.of(tester.element(_heading(2))).hasFocus, isTrue);
    expect(_heading(2).hitTestable(), findsOneWidget);
  });

  testWidgets('TC-HELP-010: contents are omitted with fewer than two named sections',
      (tester) async {
    await _pump(tester, articleId: 'short-guide');
    expect(find.byKey(_contentsKey), findsNothing);
    expect(find.text('Only section'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'TC-HELP-011: contents and jumps support $brightness with doubled text at narrow width',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester,
          brightness: brightness, scaler: const TextScaler.linear(2));
      await _tapEntry(tester, 2);
      expect(Focus.of(tester.element(_heading(2))).hasFocus, isTrue);
      expect(_heading(2).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
