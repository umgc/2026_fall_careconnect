// Verify the production route definitions with the real Settings/Help screens.
// HTTP is refused and connectivity is simulated as disconnected, without
// changing the host's network or contacting a backend.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/config/theme/app_text_scaling.dart';
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_article_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_center_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_glossary_page.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_glossary_entry.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_article_content.dart';
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
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
  bool stubLoginPage = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_fontDirectory.isNotEmpty) {
    await tester.runAsync(() async {
      for (final font in {
        'Roboto': [
          'roboto-regular.ttf',
          'roboto-medium.ttf',
          'roboto-bold.ttf'
        ],
        'MaterialIcons': ['materialicons-regular.otf'],
      }.entries) {
        final loader = FontLoader(font.key);
        for (final file in font.value) {
          final bytes = await File('$_fontDirectory/$file').readAsBytes();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }
    });
  }
  final userProvider = MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
  final theme =
      brightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme;
  late final GoRouter router;
  router = GoRouter(
    initialLocation: location,
    routes: appRouter.configuration.routes.map((route) {
      if (stubLoginPage && route is GoRoute && route.path == '/login') {
        // Keep the production dashboard/session redirect while isolating its
        // unrelated destination layout from the navigation regression.
        return GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login Page')),
        );
      }
      return route;
    }).toList(),
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
          theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: textScaler, disableAnimations: disableAnimations),
              child: AppTextScaling(router: router, child: child!)),
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

  testWidgets('Settings back arrow is safe after Back to Settings clears history',
      (tester) async {
    await _withoutNetwork((_) async {
      final router = await _pumpProductionRoutes(tester, stubLoginPage: true);
      await tester.ensureVisible(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(router.canPop(), isFalse);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The production dashboard route sends an absent stored session to login.
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(find.byType(SettingsPage), findsNothing);
    });
  });

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
      expect(find.text('No matching articles or words. Try another search.'),
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
            findsNWidgets(2));
        await tester.tap(find.text('Back to Help Center'));
        await tester.pumpAndSettle();
        expect(find.byType(HelpCenterPage), findsOneWidget);
      }
      expect(attempts.length, beforeHelp);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'Help shortcuts stay visible on every screen with large text and direct entry',
      (tester) async {
    await _withoutNetwork((_) async {
      final router = await _pumpProductionRoutes(tester,
          location: HelpRoutes.home,
          size: const Size(320, 568),
          textScaler: const TextScaler.linear(2));
      for (final location in [
        HelpRoutes.home,
        HelpRoutes.topic(HelpCategoryIds.gettingStarted),
        HelpRoutes.article(HelpArticleIds.gettingStarted),
        HelpRoutes.topic('missing-topic'),
        HelpRoutes.article('missing-article'),
        HelpRoutes.glossary,
        HelpRoutes.glossaryTerm('evv'),
        HelpRoutes.glossaryTerm('missing-word'),
      ]) {
        for (final shortcut in {
          'Help Center Home': HelpRoutes.home,
          'Back to Settings': '/settings',
        }.entries) {
          router.go(location);
          await tester.pumpAndSettle();
          expect(find.text('Help Center Home').hitTestable(), findsOneWidget);
          expect(find.text('Back to Settings').hitTestable(), findsOneWidget);
          for (final label in ['Help Center Home', 'Back to Settings']) {
            expect(
                find.descendant(
                    of: find.byType(AppBar), matching: find.text(label)),
                findsOneWidget);
          }
          final scrollable = find.byType(Scrollable).first;
          await tester.drag(scrollable, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(find.text(shortcut.key).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(shortcut.key));
          await tester.pumpAndSettle();
          expect(
              router.routeInformationProvider.value.uri.path, shortcut.value);
          expect(router.canPop(), isFalse);
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  for (final shortcut in {
    'Help Center Home': HelpRoutes.home,
    'Back to Settings': '/settings',
  }.entries) {
    testWidgets('${shortcut.key} exits a chain of related articles in one tap',
        (tester) async {
      await _withoutNetwork((_) async {
        final catalog = HelpRepository.bundled();
        final router = await _pumpProductionRoutes(tester);
        await tester.ensureVisible(find.text('Help'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Help'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Getting Started'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Getting Started'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Getting started with CareConnect'));
        await tester.pumpAndSettle();
        for (final id in [
          HelpArticleIds.readingHelp,
          HelpArticleIds.openingHelp,
          HelpArticleIds.readingHelp,
        ]) {
          final link = find.text(catalog.findArticle(id)!.title).last;
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
        }
        // Ordinary Back still returns to the previous article.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<HelpArticlePage>(find.byType(HelpArticlePage))
                .articleId,
            HelpArticleIds.openingHelp);
        expect(router.canPop(), isTrue);
        await tester.tap(find.text(shortcut.key));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, shortcut.value);
        expect(router.canPop(), isFalse,
            reason: 'Shortcuts clear the accumulated Help navigation stack.');
        expect(find.byType(HelpArticlePage), findsNothing);
        expect(find.byType(HelpTopicPage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets(
      'glossary entry, search, missing links and Back keep navigation predictable offline',
      (tester) async {
    await _withoutNetwork((attempts) async {
      final router =
          await _pumpProductionRoutes(tester, location: HelpRoutes.home);
      final before = attempts.length;
      await tester.tap(find.byKey(const ValueKey('help-open-glossary')));
      await tester.pumpAndSettle();
      expect(find.byType(HelpGlossaryEntry), findsNWidgets(75));
      expect(
          tester
              .widget<HelpGlossaryEntry>(find.byType(HelpGlossaryEntry).first)
              .term
              .term,
          'Account');
      await tester.enterText(find.byType(TextField), 'what is evv?');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-glossary-evv')), findsOneWidget);
      await _capture(tester, 'desktop-glossary-search');
      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pumpAndSettle();
      expect(find.byType(HelpGlossaryEntry), findsNothing);
      await tester.tap(find.text('Show all words'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpGlossaryEntry), findsNWidgets(75));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HelpCenterPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'what is EVV?');
      await tester.pumpAndSettle();
      expect(find.text('Articles'), findsOneWidget);
      expect(find.text('Words and meanings'), findsOneWidget);
      final result = find.byKey(const ValueKey('help-word-result-evv'));
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(
          GoRouterState.of(tester.element(find.byType(HelpGlossaryPage)))
              .uri
              .queryParameters['term'],
          'evv');
      expect(find.byKey(const ValueKey('help-glossary-evv')).hitTestable(),
          findsOneWidget);
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'EVV');
      await _capture(tester, 'desktop-glossary-selected');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'what is EVV?');
      await tester.enterText(
          find.byType(TextField), 'what does gamification mean');
      await tester.pumpAndSettle();
      expect(find.text('Articles'), findsNothing);
      expect(find.text('Words and meanings'), findsOneWidget);
      expect(find.text('No matching articles or words. Try another search.'),
          findsNothing);
      router.go(HelpRoutes.glossaryTerm('missing-word'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'That word could not be found. You can search or browse all words below.'),
          findsOneWidget);
      expect(find.byType(HelpGlossaryEntry), findsNWidgets(75));
      expect(attempts.length, before);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('word results announce both counts and open by keyboard',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _withoutNetwork((attempts) async {
        await _pumpProductionRoutes(tester, location: HelpRoutes.home);
        await tester.enterText(find.byType(TextField), 'points and rewards');
        await tester.pumpAndSettle();
        final status = tester
            .getSemantics(find.byKey(const ValueKey('help-search-status')))
            .getSemanticsData();
        expect(status.flagsCollection.isLiveRegion, isTrue);
        expect(status.label, 'No Help articles found. 1 glossary word found.');
        final result = tester
            .getSemantics(
                find.byKey(const ValueKey('help-word-result-gamification')))
            .getSemanticsData();
        expect(result.flagsCollection.isButton, isTrue);
        expect(result.label, contains('Gamification'));
        expect(result.label, contains('points or rewards'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<HelpGlossaryPage>(find.byType(HelpGlossaryPage))
                .termId,
            'gamification');
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'Gamification');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'points and rewards');
        expect(attempts, isEmpty);
      });
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'article meanings join contents navigation and open a focused glossary definition',
      (tester) async {
    await _withoutNetwork((attempts) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpProductionRoutes(tester,
            location: HelpRoutes.article(HelpArticleIds.viewingAppointments));
        final content =
            tester.widget<HelpArticleContent>(find.byType(HelpArticleContent));
        final sectionIndex = content.article.sections.length;
        final menu = find.byKey(ValueKey('help-contents-entry-$sectionIndex'));
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final heading =
            find.byKey(ValueKey('help-section-heading-$sectionIndex'));
        expect(Focus.of(tester.element(heading)).hasFocus, isTrue);
        expect(
            tester
                .getSemantics(heading)
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue);
        final link = find.text('See EVV in glossary');
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(
            GoRouterState.of(tester.element(find.byType(HelpGlossaryPage)))
                .uri
                .toString(),
            HelpRoutes.glossaryTerm('evv'));
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'EVV');
        final entry = find.byKey(const ValueKey('help-glossary-evv'));
        expect(tester.widget<HelpGlossaryEntry>(entry).selected, isTrue);
        final guide = find.descendant(
            of: entry, matching: find.text('Viewing appointments'));
        await tester.ensureVisible(guide);
        await tester.pumpAndSettle();
        await tester.tap(guide);
        await tester.pumpAndSettle();
        expect(find.byType(HelpArticlePage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(HelpGlossaryPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(HelpArticlePage), findsOneWidget);
        expect(attempts, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'glossary handles $brightness, double text, reduced motion and keyboard search at 320px',
        (tester) async {
      await _withoutNetwork((attempts) async {
        final router = await _pumpProductionRoutes(tester,
            location: HelpRoutes.glossaryTerm('text-to-speech'),
            size: const Size(320, 568),
            textScaler: const TextScaler.linear(2),
            brightness: brightness,
            disableAnimations: true);
        expect(
            FocusManager.instance.primaryFocus!.debugLabel, 'Text-to-speech');
        expect(find.text('Help Center Home').hitTestable(), findsOneWidget);
        expect(find.text('Back to Settings').hitTestable(), findsOneWidget);
        expect(find.widgetWithText(FloatingActionButton, 'Back to top'),
            findsOneWidget);
        await tester
            .tap(find.widgetWithText(FloatingActionButton, 'Back to top'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FloatingActionButton, 'Back to top'),
            findsNothing);
        expect(
            tester
                .widget<SingleChildScrollView>(
                    find.byKey(const ValueKey('help-page-scroll')))
                .controller!
                .offset,
            0);
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'points and rewards');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('help-glossary-gamification')),
            findsOneWidget);
        final definition = HelpRepository.bundled()
            .findGlossaryTerm('gamification')!
            .definition;
        final text = tester.widget<Text>(find.text(definition));
        final theme = Theme.of(tester.element(find.text(definition)));
        expect(text.style, theme.textTheme.bodyLarge);
        expect(text.style!.fontWeight, FontWeight.w500);
        expect(tester.widget<Text>(find.text('Gamification')).style!.fontWeight,
            FontWeight.w700);
        final luminance = text.style!.color!.computeLuminance();
        final background = theme.colorScheme.surface.computeLuminance();
        final contrast = luminance > background
            ? (luminance + 0.05) / (background + 0.05)
            : (background + 0.05) / (luminance + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        for (final foreground in [
          theme.colorScheme.primary,
          theme.inputDecorationTheme.labelStyle!.color!,
          theme.inputDecorationTheme.floatingLabelStyle!.color!,
          theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
        ]) {
          final luminance = foreground.computeLuminance();
          final contrast = luminance > background
              ? (luminance + 0.05) / (background + 0.05)
              : (background + 0.05) / (luminance + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
        final outline = theme
            .inputDecorationTheme.enabledBorder!.borderSide.color
            .computeLuminance();
        expect(
            (outline > background
                ? (outline + 0.05) / (background + 0.05)
                : (background + 0.05) / (outline + 0.05)),
            greaterThanOrEqualTo(3));
        await tester.ensureVisible(find.text('Gamification'));
        await tester.pumpAndSettle();
        await _capture(tester, 'phone-glossary-${brightness.name}-large-text');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty);
        router.go(HelpRoutes.glossaryTerm('evv'));
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'EVV');
        expect(attempts, isEmpty);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets(
      'all Help surfaces provide readable visual accessibility captures',
      (tester) async {
    if (_captureDirectory.isEmpty) return;
    await _withoutNetwork((_) async {
      for (final brightness in Brightness.values) {
        for (final layout in {
          'phone': (const Size(390, 844), TextScaler.noScaling),
          'large': (const Size(320, 568), const TextScaler.linear(2)),
          'landscape': (const Size(844, 390), const TextScaler.linear(2)),
        }.entries) {
          final router = await _pumpProductionRoutes(tester,
              location: HelpRoutes.home,
              brightness: brightness,
              size: layout.value.$1,
              textScaler: layout.value.$2);
          for (final route in {
            'home': HelpRoutes.home,
            'topic': HelpRoutes.topic(HelpCategoryIds.gettingStarted),
            'article': HelpRoutes.article(HelpArticleIds.recordingDose),
            'glossary': HelpRoutes.glossaryTerm('evv'),
          }.entries) {
            router.go(route.value);
            await tester.pumpAndSettle();
            await _capture(
                tester, 'audit-${brightness.name}-${layout.key}-${route.key}');
            expect(tester.takeException(), isNull);
          }
        }
      }
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
        // Exercise the generated menu against every bundled article while
        // network access is refused and text is enlarged.
        final entries = tester
            .widgetList<TextButton>(find.descendant(
                of: find.byKey(const ValueKey('help-article-contents')),
                matching: find.byType(TextButton)))
            .where((button) =>
                button.key != const ValueKey('help-contents-toggle'))
            .toList();
        expect(entries.length, greaterThanOrEqualTo(2));
        for (final entry in entries) {
          final entryFinder = find.byKey(entry.key!);
          await tester.ensureVisible(entryFinder);
          await tester.pumpAndSettle();
          final label =
              find.descendant(of: entryFinder, matching: find.byType(Text));
          await tester.tapAt(tester.getTopLeft(label) + const Offset(10, 10));
          await tester.pumpAndSettle();
          final entryKey = entry.key! as ValueKey<String>;
          final index = entryKey.value.replaceFirst('help-contents-entry-', '');
          final heading = find.byKey(ValueKey('help-section-heading-$index'));
          expect(Focus.of(tester.element(heading)).hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        }
        for (final section
            in article.sections.whereType<HelpRelatedArticles>()) {
          for (final relatedId in section.articleIds) {
            final target = catalog.findArticle(relatedId)!;
            final link = find.text(target.title).last;
            await tester.ensureVisible(link);
            await tester.pumpAndSettle();
            // At doubled text a long link can exceed the remaining viewport;
            // activate its visible first line rather than its offscreen center.
            await tester.tapAt(tester.getTopLeft(link) + const Offset(10, 10));
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
