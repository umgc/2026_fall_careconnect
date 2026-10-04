import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_article_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pumpHelp(WidgetTester tester,
    {String location = HelpRoutes.home,
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
    locale: const Locale('en'),
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
