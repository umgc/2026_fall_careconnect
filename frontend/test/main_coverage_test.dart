// Coverage tests for lib/main.dart: deep-link handling, the global error
// boundary widget and the main() bootstrap path.

import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:care_connect_app/main.dart' as app;
import 'package:care_connect_app/main.dart';
import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/messaging_service.dart';

import 'test_support/fake_web_socket_channel.dart';
import 'test_support/local_db_test_bindings.dart';

const _linksMethod = MethodChannel('com.llfbandit.app_links/messages');
const _connectivity =
    MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    EventChannel('dev.fluttercommunity.plus/connectivity_status');
const _linksEvents = EventChannel('com.llfbandit.app_links/events');

MockClient _mockClient() => MockClient((req) async {
      if (req.url.path.contains('/test/health')) {
        return http.Response(jsonEncode({'status': 'healthy'}), 200);
      }
      return http.Response(jsonEncode({'enabled': false}), 200);
    });

Future<void> _pumpApp(WidgetTester tester, Widget child) async {
  final themeProvider = ThemeProvider();
  final localeProvider = LocaleProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: localeProvider),
      ],
      child: child,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_linksMethod, null);
    messenger.setMockStreamHandler(_linksEvents, null);
  });

  testWidgets('handles initial OAuth link and streamed Epic links',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_linksMethod, (call) async {
      if (call.method == 'getInitialLink') {
        return 'careconnect://oauth/callback?code=abc';
      }
      return null;
    });
    messenger.setMockStreamHandler(
      _linksEvents,
      MockStreamHandler.inline(
        onListen: (args, sink) {
          sink.success('careconnect://epic/linked?status=ok');
          sink.success('careconnect://epic/linked?status=error');
          sink.success('https://example.org/other');
          sink.error(code: 'ERR', message: 'boom');
        },
      ),
    );

    final mock = _mockClient();
    ApiService.debugSetHttpClient(mock);
    try {
      await http.runWithClient(() async {
        await _pumpApp(tester, const CareConnectApp());
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(MaterialApp), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }, () => mock);
    } finally {
      ApiService.debugResetHttpClient();
    }
  });

  testWidgets('initial link lookup error is tolerated', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_linksMethod, (call) async {
      throw PlatformException(code: 'nope');
    });

    final mock = _mockClient();
    ApiService.debugSetHttpClient(mock);
    try {
      await http.runWithClient(() async {
        await _pumpApp(tester, const CareConnectApp());
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(MaterialApp), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }, () => mock);
    } finally {
      ApiService.debugResetHttpClient();
    }
  });

  testWidgets('error boundary installs a friendly ErrorWidget builder',
      (tester) async {
    final originalBuilder = ErrorWidget.builder;
    final mock = _mockClient();
    ApiService.debugSetHttpClient(mock);
    try {
      await http.runWithClient(() async {
        await _pumpApp(tester, const CareConnectAppWithErrorBoundary());
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(CareConnectApp), findsOneWidget);

        // Unknown route renders the router's "Page Not Found" error page.
        appRouter.go('/definitely-not-a-real-route');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Page Not Found'), findsWidgets);
        await tester.tap(find.text('Home'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        final errorUi = ErrorWidget.builder(
          FlutterErrorDetails(exception: Exception('kaboom')),
        );
        await tester.pumpWidget(errorUi);
        await tester.pump();
        expect(find.text('Something went wrong'), findsOneWidget);
        expect(find.textContaining('kaboom'), findsOneWidget);
        expect(find.text('Go Home'), findsOneWidget);
        await tester.tap(find.text('Go Home'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }, () => mock);
    } finally {
      ErrorWidget.builder = originalBuilder;
      ApiService.debugResetHttpClient();
    }
  });

  testWidgets('main() boots the app with providers', (tester) async {
    await tester.runAsync(LocalDbTestBindings.install);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_connectivity, (call) async {
      return <String>['wifi'];
    });
    messenger.setMockStreamHandler(
      _connectivityStatus,
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    messenger.setMockMethodCallHandler(_linksMethod, (call) async => null);
    final originalBuilder = ErrorWidget.builder;
    final originalOnError = FlutterError.onError;
    final originalPlatformOnError = PlatformDispatcher.instance.onError;
    final socket = FakeWebSocketChannel();
    MessagingService.connectChannel = (_) => socket;
    final mock = _mockClient();
    ApiService.debugSetHttpClient(mock);
    try {
      await http.runWithClient(() async {
        await tester.runAsync(() async {
          await app.main();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(CareConnectApp), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }, () => mock);
    } finally {
      ErrorWidget.builder = originalBuilder;
      FlutterError.onError = originalOnError;
      PlatformDispatcher.instance.onError = originalPlatformOnError;
      MessagingService.resetForTest();
      MessagingService.connectChannel = WebSocketChannel.connect;
      ApiService.debugResetHttpClient();
      messenger.setMockMethodCallHandler(_connectivity, null);
      messenger.setMockStreamHandler(_connectivityStatus, null);
      await tester.runAsync(LocalDbTestBindings.uninstall);
    }
  });
}
