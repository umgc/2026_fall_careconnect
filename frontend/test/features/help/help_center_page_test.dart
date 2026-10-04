import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_article_tile.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_topic_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pumpHelp(WidgetTester tester,
    {String location = HelpRoutes.home,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
    TextScaler textScaler = TextScaler.noScaling}) async {
  final catalog = HelpRepository.bundled();
  final router = GoRouter(initialLocation: location, routes: [
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
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
    locale: locale,
    theme: (brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme)
        .copyWith(
            textTheme: (brightness == Brightness.light
                    ? AppTheme.lightTheme
                    : AppTheme.darkTheme)
                .textTheme
                .apply(fontFamily: 'Roboto')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty results can browse visible topics with keyboard focus',
      (tester) async {
    await _pumpHelp(tester);
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Clear search.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Browse Topics.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    final firstTopic =
        tester.widget<HelpTopicTile>(find.byType(HelpTopicTile).first);
    expect(firstTopic.focusNode!.hasFocus, isTrue);
    expect(find.text('Getting Started').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<HelpTopicPage>(find.byType(HelpTopicPage)).categoryId,
        HelpCategoryIds.gettingStarted);
  });

  testWidgets('Tab and Shift-Tab traverse search controls; Enter opens a guide',
      (tester) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
        () => FocusManager.instance.highlightStrategy = previousStrategy);
    await _pumpHelp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Help Center Home.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Back to Settings.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final searchFocus =
        tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(searchFocus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'meds');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(searchFocus.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(searchFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
        tester.widget<HelpArticlePage>(find.byType(HelpArticlePage)).articleId,
        HelpArticleIds.recordingDose);
  });

  testWidgets(
      'screen readers receive article labels, topic buttons and result announcements',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpHelp(tester);
      final articleData = tester
          .getSemantics(
              find.byKey(const ValueKey(HelpArticleIds.gettingStarted)))
          .getSemanticsData();
      expect(articleData.flagsCollection.isButton, isTrue);
      expect(articleData.label, contains('Getting started with CareConnect'));
      expect(articleData.label,
          contains('Learn where to find your care information'));
      await tester.ensureVisible(find.text('Medications'));
      final topicData = tester
          .getSemantics(find.widgetWithText(HelpTopicTile, 'Medications'))
          .getSemanticsData();
      expect(topicData.flagsCollection.isButton, isTrue);
      expect(topicData.label, contains('Medications'));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'meds');
      await tester.pumpAndSettle();
      final resultData = tester
          .getSemantics(find.byKey(const ValueKey('help-search-status')))
          .getSemanticsData();
      expect(resultData.flagsCollection.isLiveRegion, isTrue);
      expect(resultData.flagsCollection.isHeader, isTrue);
      expect(resultData.label, '1 Help article found');
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pumpAndSettle();
      expect(
          tester
              .getSemantics(find.byKey(const ValueKey('help-search-status')))
              .getSemanticsData()
              .label,
          'No Help articles found');
    } finally {
      semantics.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'Help uses shared typography and readable colors in $brightness',
        (tester) async {
      await _pumpHelp(tester, brightness: brightness);
      final theme = Theme.of(tester.element(find.byType(HelpCenterPage)));
      final article = tester
          .widget<HelpArticleTile>(find.byType(HelpArticleTile).first)
          .article;
      final topic = tester
          .widget<HelpTopicTile>(find.byType(HelpTopicTile).first)
          .category;
      for (final title in [article.title, topic.title]) {
        expect(tester.widget<Text>(find.text(title)).style,
            theme.textTheme.titleMedium);
      }
      for (final description in [article.summary, topic.description]) {
        final text = tester.widget<Text>(find.text(description));
        expect(text.style, theme.textTheme.bodyLarge);
        expect(text.style!.fontFamily, 'Roboto');
        expect(text.style!.fontSize, 16);
        final luminance = text.style!.color!.computeLuminance();
        final background = theme.colorScheme.surface.computeLuminance();
        final contrast = luminance > background
            ? (luminance + 0.05) / (background + 0.05)
            : (background + 0.05) / (luminance + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      final heading = tester.widget<Text>(find.text('Popular Help'));
      expect(heading.style, theme.textTheme.displaySmall);
      expect(heading.style!.fontWeight, FontWeight.bold);
      expect(tester.widget<TextField>(find.byType(TextField)).style,
          theme.textTheme.bodyLarge);
    });

    testWidgets(
        'empty results, topic browsing and articles support $brightness and large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHelp(tester,
          brightness: brightness, textScaler: const TextScaler.linear(2));
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.widgetWithText(OutlinedButton, 'Browse Topics'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse Topics'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Getting Started'));
      await tester.tap(find.text('Getting Started'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(HelpTopicPage))).brightness,
          brightness);
      await tester.ensureVisible(find.text('Reading Help articles'));
      await tester.tap(find.text('Reading Help articles'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Web').last);
      expect(Theme.of(tester.element(find.byType(HelpArticlePage))).brightness,
          brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('untranslated Help labels and content fall back to English',
      (tester) async {
    await _pumpHelp(tester, locale: const Locale('es'));
    expect(find.text('Help Center'), findsOneWidget);
    expect(find.text('Getting started with CareConnect'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'meds');
    await tester.pumpAndSettle();
    final t = AppLocalizations.of(tester.element(find.byType(HelpCenterPage)))!;
    expect(t.helpSearchResultsCount(1), '1 Help article found');
    expect(t.helpSearchResultsCount(2), '2 Help articles found');
  });

  testWidgets('home shows requested headings and six guides in explicit order',
      (tester) async {
    await _pumpHelp(tester);
    expect(find.text('Help Center'), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'Search Help articles'), findsOneWidget);
    expect(find.text('Popular Help'), findsOneWidget);
    expect(find.text('Browse Topics'), findsOneWidget);
    expect(
        tester
            .widgetList<HelpArticleTile>(find.byType(HelpArticleTile))
            .map((tile) => tile.article.id),
        [
          HelpArticleIds.gettingStarted,
          HelpArticleIds.recordingDose,
          HelpArticleIds.dailyCheckIn,
          HelpArticleIds.viewingAppointments,
          HelpArticleIds.messagingCaregiver,
          HelpArticleIds.resettingPassword,
        ]);
    await tester.ensureVisible(find.text('Account and Settings'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'local search opens a result and keeps query after back; clear restores home',
      (tester) async {
    await _pumpHelp(tester);
    await tester.enterText(find.byType(TextField), '  DOSE  ');
    await tester.pumpAndSettle();
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('Popular Help'), findsNothing);
    await tester.tap(find.text('Viewing medications and recording a dose'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<HelpArticlePage>(find.byType(HelpArticlePage)).articleId,
        HelpArticleIds.recordingDose);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  DOSE  ');
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pumpAndSettle();
    expect(
        find.text('No matching articles. Try another search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Popular Help'), findsOneWidget);
    expect(find.byType(HelpArticleTile), findsNWidgets(6));
  });

  testWidgets(
      'Browse Topics opens a category then an article and returns through both screens',
      (tester) async {
    await _pumpHelp(tester);
    await tester.ensureVisible(find.text('Medications'));
    await tester.tap(find.text('Medications'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpTopicPage), findsOneWidget);
    expect(find.byType(HelpArticleTile), findsOneWidget);
    await tester.tap(find.text('Viewing medications and recording a dose'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpArticlePage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HelpTopicPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HelpCenterPage), findsOneWidget);
  });

  testWidgets('unknown topic offers a working return to Help Center',
      (tester) async {
    await _pumpHelp(tester, location: HelpRoutes.topic('missing'));
    expect(find.text('Topic not found'), findsOneWidget);
    await tester.tap(find.text('Back to Help Center'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpCenterPage), findsOneWidget);
  });

  testWidgets(
      'home and topics remain scrollable at narrow width and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpHelp(tester, textScaler: const TextScaler.linear(2));
    await tester.ensureVisible(find.text('Account and Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Account and Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpTopicPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Resetting your password'));
    await tester.tap(find.text('Resetting your password'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpArticlePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
