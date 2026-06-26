import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/shortcut_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'config/router/app_router.dart';
import 'services/auth_migration_helper.dart';
import 'services/api_service.dart';
import 'services/messaging_service.dart';
import 'services/local_db/local_db_startup.dart';
import 'config/theme/app_theme.dart';
import 'config/utils/responsive_utils.dart';
import 'config/utils/web_utils.dart';
import 'features/tasks/utils/task_type_manager.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';

Future<void> main() async {
  // Global error handling for unhandled Dart errors
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Load environment variables from .env file
      await dotenv.load(fileName: ".env");

      // Global error handling for Flutter errors
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        // Optionally log to a remote server
        debugPrint(
          'FlutterError: \\n${details.exceptionAsString()}\\n${details.stack}',
        );
      };
      // Performance optimization: Set preferred orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Configure URL strategy for web to remove hash from URLs
      if (kIsWeb) {
    // For hash-based routes:
         setUrlStrategy(const HashUrlStrategy());
 
        }else{
            // Or, for path-based routes (no #):
          usePathUrlStrategy();
        }

      // Create providers (don't initialize them yet)
      final userProvider = UserProvider();
      ApiService.configureOfflineQueue(
        canQueueOfflineWrites: () => userProvider.offlineModeEnabled,
      );
      final themeProvider = ThemeProvider();
      final shortcutProvider = ShortcutProvider()..init();
      final localeProvider = LocaleProvider();
      await localeProvider.loadSaved();

      // Start the app immediately, initialize services in background
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: userProvider),
            ChangeNotifierProvider.value(value: themeProvider),
            ChangeNotifierProvider.value(value: shortcutProvider),
            ChangeNotifierProvider.value(value: localeProvider),
            ChangeNotifierProvider(create: (_) => TaskTypeManager()),
          ],
          child: CareConnectAppWithErrorBoundary(),
        ),
      );

      // Initialize heavy services in background after app starts
      _initializeServicesInBackground(userProvider);
    },
    (error, stack) {
      // Use print() not debugPrint() — debugPrint is a no-op in release mode,
      // which silently swallows startup crashes and leaves the loading screen stuck.
      // ignore: avoid_print
      print('🔴 Uncaught error (runZonedGuarded): $error\n$stack');
    },
  );
}

/// Top-level error boundary widget for global error UI
class CareConnectAppWithErrorBoundary extends StatefulWidget {
  const CareConnectAppWithErrorBoundary({super.key});

  @override
  State<CareConnectAppWithErrorBoundary> createState() =>
      _CareConnectAppWithErrorBoundaryState();
}

class _CareConnectAppWithErrorBoundaryState
    extends State<CareConnectAppWithErrorBoundary> {
  @override
  void initState() {
    super.initState();
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // You can customize this error UI as needed
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      appRouter.go('/');
                    },
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return const CareConnectApp();
  }
}

// Background initialization to not block app startup
Future<void> _initializeServicesInBackground(UserProvider userProvider) async {
  try {
    await _bootstrap();
    await userProvider.initializeUser();
    // await VideoCallService.initializeService();
    await _handleAuthMigration();

    // Only establish the WebSocket connection at this stage
    try {
      await MessagingService.initialize();
      print(
        '✅ MessagingService WebSocket connection established (user not registered yet)',
      );
    } catch (e) {
      print('⚠️ MessagingService WebSocket connection failed: $e');
      // Do not rethrow, app should continue running
    }

    print('✅ Background services initialized');
  } catch (e) {
    print('⚠️ Some background services failed to initialize: $e');
  }
}

Future<void> _handleAuthMigration() async {
  try {
    final migrationResult = await AuthMigrationHelper.migrateAuthData();
    if (!migrationResult.isSuccess && migrationResult.errorMessage != null) {
      debugPrint('Auth migration warning: ${migrationResult.errorMessage}');
    }
  } catch (e) {
    debugPrint('Auth migration error: $e');
  }
}

Future<void> _bootstrap() async {
  // Performance optimization: Warm up system caches
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await initializeLocalDbOnStartup();
  await ApiService.initializeOfflineQueue();

  // Initialize web-specific optimizations
  if (kIsWeb) {
    WebUtils.initializeWebOptimizations();
  }
}

class CareConnectApp extends StatefulWidget {
  const CareConnectApp({super.key});

  @override
  State<CareConnectApp> createState() => _CareConnectAppState();
}

class _CareConnectAppState extends State<CareConnectApp> {
  StreamSubscription? _linkSubscription;
  late AppLinks _appLinks;
  Locale? _localeOverride;

  @override
  void initState() {
    super.initState();
    _initializeDeepLinks();
  }

  Future<void> _initializeDeepLinks() async {
    _appLinks = AppLinks();

    // Check if app was opened via deep link
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink.toString());
      }
    } catch (e) {
      print('Error getting initial link: $e');
    }

    // Listen for deep links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleDeepLink(uri.toString());
      },
      onError: (err) {
        print('Deep link error: $err');
      },
    );
  }

  void _handleDeepLink(String link) {
    print('Received deep link: $link');

    // Parse the deep link to extract OAuth callback parameters
    final uri = Uri.parse(link);

    // Check if this is an OAuth callback (careconnect://oauth/callback)
    if (uri.scheme == 'careconnect' &&
        uri.host == 'oauth' &&
        uri.path == '/callback') {
      print('OAuth callback detected: $link');
      // The actual OAuth handling is done in AuthService.loginWithGoogle()
      // This is just for logging and potential additional processing
    }
  }

  @override
  void dispose() {
    if (_linkSubscription != null) {
      _linkSubscription!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

    return MaterialApp.router(
      title: 'CareConnect',
      debugShowCheckedModeBanner: false,
      // Use localized title instead of the hardcoded one above
      // onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      // Core i18n wiring
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      //  set this to the chosen locale
      locale: localeProvider.locale,

      themeMode: themeProvider.themeMode,
      theme: AppTheme.lightTheme.copyWith(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'Roboto'),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        cardTheme: CardThemeData(
          elevation: kIsWeb ? 2 : (ResponsiveUtils.isIOS ? 1 : 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ResponsiveUtils.isIOS ? 12 : 8),
          ),
        ),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        cardTheme: CardThemeData(
          elevation: kIsWeb ? 3 : (ResponsiveUtils.isIOS ? 2 : 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ResponsiveUtils.isIOS ? 12 : 8),
          ),
        ),
      ),
      routerConfig: appRouter,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final textScaleFactor = mediaQuery.textScaleFactor.clamp(0.8, 1.2);
        Widget updatedChild = child!;
        updatedChild = SafeArea(
          bottom: !ResponsiveUtils.isWeb,
          child: updatedChild,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
            devicePixelRatio: ResponsiveUtils.isWeb
                ? mediaQuery.devicePixelRatio
                : mediaQuery.devicePixelRatio.clamp(1.0, 3.0),
          ),
          child: updatedChild,
        );
      },
    );
  }
}
