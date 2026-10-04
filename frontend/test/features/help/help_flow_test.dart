// Verify the production route definitions with the real Settings/Help screens.
// HTTP is refused and connectivity is simulated as disconnected, without
// changing the host's network or contacting a backend.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mock_user_provider.dart';

const _captureKey = ValueKey('help-flow-capture');
const _captureDirectory = String.fromEnvironment('HELP_CAPTURE_DIR');
const _fontDirectory = String.fromEnvironment('HELP_FONT_DIR');

class _RefusedHttpClient extends Mock implements HttpClient {
  _RefusedHttpClient(this.attempts);
  final List<Uri> attempts;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    attempts.add(url);
    throw const SocketException('Network refused by Help verification');
  }
}

Future<void> _withoutNetwork(Future<void> Function(List<Uri>) verify) async {
  final attempts = <Uri>[];
  await HttpOverrides.runZoned(() => verify(attempts),
      createHttpClient: (_) => _RefusedHttpClient(attempts));
}

Future<GoRouter> _pumpProductionRoutes(
  WidgetTester tester, {
  String location = '/settings',
  Size size = const Size(1366, 900),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_fontDirectory.isNotEmpty) {
    await tester.runAsync(() async {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final bytes = await File('$_fontDirectory/${font.value}').readAsBytes();
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
  }
  final userProvider = MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
  late final GoRouter router;
  router = GoRouter(
    initialLocation: location,
    routes: appRouter.configuration.routes,
    observers: [TelemetryGoRouterObserver(routerProvider: () => router)],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    userProvider.dispose();
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp.router(
          locale: const Locale('en'),
          theme:
              ThemeData(fontFamily: _fontDirectory.isEmpty ? null : 'Roboto'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!),
        )),
  ));
  await tester.pumpAndSettle();
  expect(userProvider.isDeviceOnline, isFalse);
  return router;
}

/// Optional visual QA artifacts; ordinary test runs do not write screenshots.
Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_captureDirectory).create(recursive: true);
      await File('$_captureDirectory/$name.png').writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('dev.fluttercommunity.plus/connectivity'),
    MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'telemetry_opted_out': true,
      'telemetry_seen_optout_dialog': true,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channels[0], (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(
        channels[1], (call) async => call.method == 'check' ? ['none'] : null);
    messenger.setMockMethodCallHandler(channels[2], (_) async => null);
  });
  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  for (final layout in {
    'desktop': const Size(1366, 900),
    'phone': const Size(390, 844)
  }.entries) {
    testWidgets(
        'disconnected ${layout.key}: Settings first entry through Topic and Article back to Settings',
        (tester) async {
      await _withoutNetwork((attempts) async {
        final router = await _pumpProductionRoutes(tester, size: layout.value);
        await tester.scrollUntilVisible(find.text('General'), 500,
            scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.text('Help'));
        await Scrollable.ensureVisible(tester.element(find.text('General')),
            alignment: 0);
        await tester.pumpAndSettle();
        final list = tester.widget<ListView>(find.byType(ListView));
        final entries =
            (list.childrenDelegate as SliverChildListDelegate).children;
        final general = entries.indexWhere((child) => find
            .descendant(
                of: find.byWidget(child), matching: find.text('General'))
            .evaluate()
            .isNotEmpty);
        expect(general, greaterThanOrEqualTo(0));
        expect(
            find.descendant(
                of: find.byWidget(entries[general + 1]),
                matching: find.text('Help')),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byWidget(entries[general + 2]),
                matching: find.text('Offline Persistence')),
            findsOneWidget);
        await _capture(tester, '${layout.key}-settings-general');
        expect(attempts, isNotEmpty,
            reason: 'Settings requests were refused, not served by a backend.');
        final beforeHelp = attempts.length;
        await tester.tap(find.text('Help'));
        await tester.pumpAndSettle();
        expect(find.byType(HelpCenterPage), findsOneWidget);
        await _capture(tester, '${layout.key}-help-home');
        await tester.ensureVisible(find.text('Medications'));
        await tester.tap(find.text('Medications'));
        await tester.pumpAndSettle();
        expect(
            GoRouterState.of(tester.element(find.byType(HelpTopicPage)))
                .uri
                .path,
            HelpRoutes.topic(HelpCategoryIds.medications));
        await _capture(tester, '${layout.key}-help-topic');
        await tester.tap(find.text('Viewing medications and recording a dose'));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<HelpArticlePage>(find.byType(HelpArticlePage))
                .articleId,
            HelpArticleIds.recordingDose);
        await _capture(tester, '${layout.key}-help-article');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(HelpTopicPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(HelpCenterPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(attempts.length, beforeHelp,
            reason: 'Reading Help must not request network content.');
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets(
      'disconnected production routes: keywords, empty browsing and missing content recovery',
      (tester) async {
    await _withoutNetwork((attempts) async {
      final router =
          await _pumpProductionRoutes(tester, location: HelpRoutes.home);
      final beforeHelp = attempts.length;
      await tester.enterText(find.byType(TextField), 'medicine');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewing medications and recording a dose'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpArticlePage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'medicine');
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pumpAndSettle();
      expect(find.text('No matching articles. Try another search.'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse Topics'));
      await tester.pumpAndSettle();
      expect(find.text('Getting Started').hitTestable(), findsOneWidget);
      for (final location in [
        HelpRoutes.article('missing-article'),
        HelpRoutes.topic('missing-topic')
      ]) {
        router.go(location);
        await tester.pumpAndSettle();
        expect(
            find.text(location.contains('/articles/')
                ? 'Article not found'
                : 'Topic not found'),
            findsOneWidget);
        await tester.tap(find.text('Back to Help Center'));
        await tester.pumpAndSettle();
        expect(find.byType(HelpCenterPage), findsOneWidget);
      }
      expect(attempts.length, beforeHelp);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'all bundled IDs and related links render disconnected at double text on a narrow screen',
      (tester) async {
    await _withoutNetwork((attempts) async {
      final catalog = HelpRepository.bundled();
      final router = await _pumpProductionRoutes(tester,
          location: HelpRoutes.home,
          size: const Size(320, 568),
          textScaler: const TextScaler.linear(2));
      final beforeHelp = attempts.length;
      for (final category in catalog.categories) {
        router.go(HelpRoutes.topic(category.id));
        await tester.pumpAndSettle();
        expect(
            tester.widget<HelpTopicPage>(find.byType(HelpTopicPage)).categoryId,
            category.id);
        expect(find.text('Topic not found'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      for (final article in catalog.articles) {
        router.go(HelpRoutes.article(article.id));
        await tester.pumpAndSettle();
        expect(find.text(article.title), findsWidgets);
        for (final section
            in article.sections.whereType<HelpRelatedArticles>()) {
          for (final relatedId in section.articleIds) {
            final target = catalog.findArticle(relatedId)!;
            await tester.ensureVisible(find.text(target.title).last);
            await tester.tap(find.text(target.title).last);
            await tester.pumpAndSettle();
            expect(
                tester
                    .widget<HelpArticlePage>(find.byType(HelpArticlePage))
                    .articleId,
                relatedId);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(
                tester
                    .widget<HelpArticlePage>(find.byType(HelpArticlePage))
                    .articleId,
                article.id);
          }
        }
        expect(tester.takeException(), isNull);
      }
      expect(attempts.length, beforeHelp);
    });
  });
}
