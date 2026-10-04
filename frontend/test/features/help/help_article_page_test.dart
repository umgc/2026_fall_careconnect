// Exercise ID-based article navigation using a local catalog, without services.
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
