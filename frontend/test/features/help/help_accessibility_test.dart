import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:care_connect_app/config/theme/app_text_scaling.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_glossary_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_accessibility.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_article_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

double _contrast(Color foreground, Color background) {
  final light = Color.alphaBlend(foreground, background).computeLuminance();
  final dark = background.computeLuminance();
  return (math.max(light, dark) + 0.05) / (math.min(light, dark) + 0.05);
}

Future<GoRouter> _pump(WidgetTester tester,
    {Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    TextScaler scaler = TextScaler.noScaling,
    bool increasedSpacing = false,
    Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final catalog = HelpRepository.bundled();
  final router = GoRouter(initialLocation: HelpRoutes.home, routes: [
    GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('Settings'))),
    GoRoute(
        path: HelpRoutes.home,
        builder: (_, __) => HelpCenterPage(repository: catalog),
        routes: [
          GoRoute(
              path: HelpRoutes.topicPattern,
              builder: (_, state) => HelpTopicPage(
                  categoryId: state.pathParameters['categoryId']!,
                  repository: catalog)),
          GoRoute(
              path: HelpRoutes.articlePattern,
              builder: (_, state) => HelpArticlePage(
                  articleId: state.pathParameters['articleId']!,
                  repository: catalog)),
          GoRoute(
              path: HelpRoutes.glossaryPattern,
              builder: (_, state) => HelpGlossaryPage(
                  termId: state.uri.queryParameters['term'],
                  repository: catalog)),
        ]),
  ]);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  final theme =
      brightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme;
  await tester.pumpWidget(MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(
        textTheme: _spacedTheme(theme.textTheme, increasedSpacing)
            .apply(fontFamily: 'Roboto')),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: scaler, disableAnimations: true),
        child: AppTextScaling(router: router, child: child!)),
  ));
  await tester.pumpAndSettle();
  return router;
}

TextTheme _spacedTheme(TextTheme text, bool increase) {
  if (!increase) return text;
  TextStyle? space(TextStyle? style) => style?.copyWith(
      letterSpacing: (style.fontSize ?? 16) * 0.12,
      wordSpacing: (style.fontSize ?? 16) * 0.16,
      height: math.max(1.5, style.height ?? 1.5));
  return TextTheme(
    displayLarge: space(text.displayLarge),
    displayMedium: space(text.displayMedium),
    displaySmall: space(text.displaySmall),
    headlineLarge: space(text.headlineLarge),
    headlineMedium: space(text.headlineMedium),
    headlineSmall: space(text.headlineSmall),
    titleLarge: space(text.titleLarge),
    titleMedium: space(text.titleMedium),
    titleSmall: space(text.titleSmall),
    bodyLarge: space(text.bodyLarge),
    bodyMedium: space(text.bodyMedium),
    bodySmall: space(text.bodySmall),
    labelLarge: space(text.labelLarge),
    labelMedium: space(text.labelMedium),
    labelSmall: space(text.labelSmall),
  );
}

/// Inspect the effective text styles and nearest painted background, including
/// tinted glossary panels and input labels. Raster antialiasing is not sampled.
void _checkTextContrast(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    // Icon glyphs have the separate non-text contrast threshold.
    bool icon = false;
    Color? background;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Icon) icon = true;
      if (background == null &&
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration) {
        final color = (widget.decoration as BoxDecoration).color;
        if (color != null && color.a > 0) {
          background = color;
        }
      }
      if (background == null &&
          widget is Material &&
          widget.color != null &&
          widget.color!.a > 0) {
        background = widget.color;
      }
      return true;
    });
    if (icon) continue;
    background ??= Theme.of(element).scaffoldBackgroundColor;
    final richText = element.widget as RichText;
    void check(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is TextSpan) {
        if (span.text?.trim().isNotEmpty ?? false) {
          final color = style.color!;
          expect(_contrast(color, background!), greaterThanOrEqualTo(4.5),
              reason: '"${span.text}" on $background with $color');
          // WCAG specifies resizing rather than a universal minimum font size.
          // Help uses 16px base text; floating input labels render at 75%.
          expect(style.fontSize, greaterThanOrEqualTo(16), reason: span.text);
        }
        for (final child in span.children ?? <InlineSpan>[]) {
          check(child, style);
        }
      }
    }

    check(richText.text, DefaultTextStyle.of(element).style);
  }
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize <= 20 ? 2 : 1.5);
  @override
  double get textScaleFactor => 2;
}

void main() {
  final catalog = HelpRepository.bundled();
  for (final brightness in Brightness.values) {
    for (final layout in {
      'phone': (const Size(390, 844), TextScaler.noScaling),
      '320px and 200% text': (const Size(320, 568), const TextScaler.linear(2)),
      'landscape and 200% text': (
        const Size(844, 390),
        const TextScaler.linear(2)
      ),
    }.entries) {
      testWidgets(
          'TC-HELP-001: all Help pages: contrast, targets, headings and reflow in $brightness ${layout.key}',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final router = await _pump(tester,
              brightness: brightness,
              size: layout.value.$1,
              scaler: layout.value.$2);
          for (final location in [
            HelpRoutes.home,
            for (final topic in catalog.categories) HelpRoutes.topic(topic.id),
            for (final article in catalog.articles)
              HelpRoutes.article(article.id),
            HelpRoutes.topic('missing'),
            HelpRoutes.article('missing'),
            HelpRoutes.glossaryTerm('evv'),
            HelpRoutes.glossaryTerm('missing'),
          ]) {
            router.go(location);
            await tester.pumpAndSettle();
            final heading = find.byKey(const ValueKey('help-page-heading'));
            final data = tester.getSemantics(heading).getSemanticsData();
            expect(data.headingLevel, 1, reason: location);
            expect(data.locale, const Locale('en'), reason: location);
            expect(data.label, isNotEmpty);
            final pageTitle = tester
                .widgetList<HelpPageTitle>(find.byType(HelpPageTitle))
                .last;
            expect(pageTitle.title, '${data.label} | CareConnect Help');
            final media = MediaQuery.of(tester.element(heading));
            expect(media.textScaler, layout.value.$2);
            _checkTextContrast(tester);
            await expectLater(
                tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(
                tester, meetsGuideline(labeledTapTargetGuideline));
            final theme = Theme.of(tester.element(heading));
            expect(
                _contrast(theme.colorScheme.primary, theme.colorScheme.surface),
                greaterThanOrEqualTo(4.5));
            expect(
                _contrast(theme.colorScheme.outline, theme.colorScheme.surface),
                greaterThanOrEqualTo(3));
            expect(tester.takeException(), isNull, reason: location);
          }
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('TC-HELP-002: increased letter, word and line spacing reflows at 320px',
      (tester) async {
    final router =
        await _pump(tester, size: const Size(320, 568), increasedSpacing: true);
    for (final location in [
      HelpRoutes.home,
      for (final article in catalog.articles) HelpRoutes.article(article.id),
      HelpRoutes.glossaryTerm('evv')
    ]) {
      router.go(location);
      await tester.pumpAndSettle();
      for (final element in find.byType(RichText).evaluate()) {
        bool inHeader = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is AppBar) inHeader = true;
          return true;
        });
        if (!inHeader) {
          expect((element.renderObject! as RenderParagraph).didExceedMaxLines,
              isFalse,
              reason:
                  '$location: ${(element.widget as RichText).text.toPlainText()}');
        }
      }
      expect(tester.takeException(), isNull, reason: location);
    }
  });

  testWidgets(
      'TC-HELP-003: glossary links focus a named selected heading; Back to top restores title focus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = await _pump(tester);
      router.go(HelpRoutes.glossaryTerm('evv'));
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('help-glossary-heading-evv'));
      final data = tester.getSemantics(heading).getSemanticsData();
      expect(data.label, 'EVV');
      expect(data.headingLevel, 2);
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      expect(data.flagsCollection.isFocused, Tristate.isTrue);
      expect(Focus.of(tester.element(heading)).hasFocus, isTrue);
      await tester
          .tap(find.widgetWithText(FloatingActionButton, 'Back to top'));
      await tester.pumpAndSettle();
      expect(
          Focus.of(tester
                  .element(find.byKey(const ValueKey('help-page-heading'))))
              .hasFocus,
          isTrue);
      expect(find.widgetWithText(FloatingActionButton, 'Back to top'),
          findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'TC-HELP-004: Help preserves nonlinear scaling on entry and restores the existing policy on exit',
      (tester) async {
    final router = await _pump(tester, scaler: const _NonlinearScaler());
    final heading = find.byKey(const ValueKey('help-page-heading'));
    expect(MediaQuery.textScalerOf(tester.element(heading)),
        const _NonlinearScaler());
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(
        MediaQuery.textScalerOf(tester.element(find.text('Settings')))
            .scale(16),
        19.2);
    router.go(HelpRoutes.glossary);
    await tester.pumpAndSettle();
    expect(MediaQuery.textScalerOf(tester.element(heading)),
        const _NonlinearScaler());
  });

  testWidgets(
      'TC-HELP-005: English fallback language, unique button labels, live results and strong keyboard focus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = await _pump(tester, locale: const Locale('ar'));
      final article = find.byType(HelpArticleTile).first;
      final tile = tester.widget<HelpArticleTile>(article);
      final data = tester.getSemantics(article).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, '${tile.article.title}\n${tile.article.summary}');
      expect(data.hint, 'Opens a Help article');
      expect(data.locale, const Locale('en'));
      expect(Directionality.of(tester.element(article)), TextDirection.ltr);
      // Header shortcuts, search, glossary, then the first article.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.pumpAndSettle();
      final listTile =
          find.descendant(of: article, matching: find.byType(ListTile));
      final shape =
          tester.widget<ListTile>(listTile).shape! as RoundedRectangleBorder;
      expect(shape.side.width, 3);
      final theme = Theme.of(tester.element(listTile));
      expect(_contrast(shape.side.color, theme.colorScheme.surface),
          greaterThanOrEqualTo(3));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pumpAndSettle();
      final status = tester
          .getSemantics(find.byKey(const ValueKey('help-search-status')))
          .getSemanticsData();
      expect(status.flagsCollection.isLiveRegion, isTrue);
      expect(status.label, 'No Help articles found. No glossary words found.');
      final clear = find.byTooltip('Clear search');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('Popular Help'), findsOneWidget);
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue);
      router.go(HelpRoutes.topic('getting-started'));
      await tester.pumpAndSettle();
      final back = find.byType(BackButton);
      final backData = tester.getSemantics(back).getSemanticsData();
      expect(backData.locale, const Locale('ar'));
      expect(backData.label,
          MaterialLocalizations.of(tester.element(back)).backButtonTooltip);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
