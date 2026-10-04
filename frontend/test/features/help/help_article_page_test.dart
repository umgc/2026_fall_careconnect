// Exercise ID-based article navigation using a local catalog, without services.
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../test_support/help_test_catalog.dart';

Future<void> _pumpHelp(
  WidgetTester tester, {
  required String location,
  HelpRepository? repository,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final catalog = repository ?? createHelpTestCatalog();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: HelpRoutes.home,
        builder: (_, __) => HelpCenterPage(repository: catalog),
        routes: [
          GoRoute(
            path: HelpRoutes.articlePattern,
            builder: (_, state) => HelpArticlePage(
              articleId: state.pathParameters['articleId']!,
              repository: catalog,
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
    theme: AppTheme.lightTheme.copyWith(
        textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto')),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a direct article ID renders paragraphs, numbered steps, and tips',
      (tester) async {
    await _pumpHelp(tester, location: HelpRoutes.article(firstHelpTestId));

    expect(find.text('First guide'), findsWidgets);
    expect(find.text('Getting Started'), findsOneWidget);
    expect(find.text('A short description.'), findsOneWidget);
    expect(find.text('A helpful paragraph.'), findsOneWidget);
    expect(find.text('1. First action'), findsOneWidget);
    expect(find.text('2. Second action'), findsOneWidget);
    expect(find.text('Something failed'), findsOneWidget);
    expect(find.text('Try this fix'), findsOneWidget);
    expect(find.text('Related articles'), findsOneWidget);
    final textTheme =
        Theme.of(tester.element(find.byType(HelpArticlePage))).textTheme;
    final title = tester
        .widgetList<Text>(find.text('First guide'))
        .firstWhere((text) => text.style == textTheme.displayMedium);
    expect(title.style!.fontFamily, 'Roboto');
    expect(title.style!.fontWeight, FontWeight.bold);
    expect(tester.widget<Text>(find.text('A helpful paragraph.')).style,
        textTheme.bodyLarge);
    expect(tester.widget<Text>(find.text('Related articles')).style,
        textTheme.displaySmall);
  });

  testWidgets(
      'home opens an article; related links open another ID and back returns',
      (tester) async {
    // Arrange: start from the home screen with a catalog shared by both pages.
    await _pumpHelp(tester, location: HelpRoutes.home);

    // Act: open the first article and then its related guide.
    await tester.tap(find.text('First guide'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Second guide'));
    await tester.tap(find.text('Second guide'));
    await tester.pumpAndSettle();

    // Assert: the same reusable screen resolved the second article's ID.
    expect(
        tester.widget<HelpArticlePage>(find.byType(HelpArticlePage)).articleId,
        secondHelpTestId);
    expect(find.text('Another helpful paragraph.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester.widget<HelpArticlePage>(find.byType(HelpArticlePage)).articleId,
        firstHelpTestId);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HelpCenterPage), findsOneWidget);
  });

  testWidgets('an unknown ID provides a working return to Help Center',
      (tester) async {
    await _pumpHelp(tester, location: HelpRoutes.article('missing-article'));
    expect(find.text('Article not found'), findsOneWidget);
    await tester.tap(find.text('Back to Help Center'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpCenterPage), findsOneWidget);
    expect(find.byType(HelpArticlePage), findsNothing);
  });

  testWidgets(
      'Back to top appears after scrolling, hides near the top, and returns to the beginning',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpHelp(tester,
        location: HelpRoutes.article(firstHelpTestId),
        repository: createHelpTestCatalog(
            paragraph:
                List.filled(60, 'A long paragraph with helpful instructions.')
                    .join(' ')),
        textScaler: const TextScaler.linear(2));
    final scrollView = find.byType(SingleChildScrollView);
    final controller =
        tester.widget<SingleChildScrollView>(scrollView).controller!;
    expect(find.text('Back to top'), findsNothing);
    await tester.drag(scrollView, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Back to top').hitTestable(), findsOneWidget);
    final button = find.byType(FloatingActionButton);
    expect(tester.getRect(button).left, lessThan(30));
    expect(tester.getRect(button).bottom, greaterThan(500));
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    expect(find.text('Back to top'), findsNothing);
    controller.jumpTo(600);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to top'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.text('Back to top'), findsNothing);
    expect(find.text('Getting Started').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short articles do not show Back to top', (tester) async {
    await _pumpHelp(tester, location: HelpRoutes.article(secondHelpTestId));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Back to top'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long content remains scrollable with large text on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paragraph =
        List.filled(60, 'A long paragraph that wraps onto more lines.')
            .join(' ');

    await _pumpHelp(
      tester,
      location: HelpRoutes.article(firstHelpTestId),
      repository: createHelpTestCatalog(paragraph: paragraph),
      textScaler: const TextScaler.linear(2),
    );
    await tester.ensureVisible(find.text('Second guide'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Second guide'));
    await tester.pumpAndSettle();
    expect(find.text('Another helpful paragraph.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
