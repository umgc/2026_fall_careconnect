// Flow tests for UspsTestScreen
// (lib/features/usps/presentation/usps_test_screen.dart) with a signed-in
// user and a faked backend: Gmail status, digest lists, item dialogs, search,
// clear cache, connect and disconnect.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/usps/presentation/usps_test_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../helpers/json_http_overrides.dart';
import '../../../mock_user_provider.dart';

const _png1x1 =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

final _digest = <String, dynamic>{
  'mailpieces': [
    {
      'sender': 'Acme Bank',
      'summary': 'Monthly statement',
      'imageDataUrl': _png1x1,
      'deliveryDate': '2026-10-01',
      'actions': {
        'dashboard': 'https://informeddelivery.example/dashboard',
        'track': 'https://tools.example/track/1',
      },
    },
    {
      'subject': 'Flyer only',
      'thumbnailUrl': 'cid:abc',
    },
    {
      'sender': 'Http Image Co',
      'imageDataUrl': 'https://img.example/x.png',
    },
    {
      'sender': 'Bad Data',
      'imageDataUrl': 'data:image/png;base64,%%%notbase64',
    },
    'not-a-map',
  ],
  'packages': [
    {
      'sender': 'Parcel Shop',
      'trackingNumber': '9400100000000000000000',
      'expectedDateIso': '2026-10-05',
      'actions': {'track': 'https://tools.example/track/pkg'},
    },
    {
      'trackingNumber': '9400200000000000000000',
      'actions': {'dashboard': 'https://informeddelivery.example/dashboard'},
    },
    42,
  ],
};

final _searchResults = [
  {
    'type': 'package',
    'sender': 'Search Parcel',
    'trackingNumber': 'TRK123',
    'expectedDate': '10/09/2026',
    'actions': {'track': 'https://tools.example/track/s1'},
  },
  {
    'type': 'mail',
    'sender': 'Search Sender',
    'summary': 'Search summary',
    'imageDataUrl': _png1x1,
    'deliveryDate': '2026-10-02',
    'actions': {'dashboard': 'https://informeddelivery.example/d2'},
  },
  {
    'subject': 'No sender result',
  },
];

class _Backend {
  _Backend({
    this.status = const {'connected': true, 'status': 'CONNECTED'},
    this.digestStatus = 200,
    this.searchStatus = 200,
    this.search,
    this.connectUrl = '/oauth/google/start',
    this.failDelete = false,
    this.failClearCache = false,
  });

  Map<String, dynamic> status;
  int digestStatus;
  int searchStatus;
  List<Map<String, dynamic>>? search;
  String? connectUrl;
  bool failDelete;
  bool failClearCache;

  JsonReply call(String method, Uri uri, String body) {
    final p = uri.path;
    if (p.endsWith('/email-credentials/status')) {
      return JsonReply(200, status);
    }
    if (p.endsWith('/usps/latest')) {
      if (digestStatus == 200) return JsonReply(200, _digest);
      return JsonReply(digestStatus);
    }
    if (p.endsWith('/usps/search')) {
      if (searchStatus != 200) return JsonReply(searchStatus, {'e': 'x'});
      return JsonReply(200, search ?? _searchResults);
    }
    if (p.endsWith('/usps/clear-cache')) {
      return failClearCache ? JsonReply(500, {'e': 'x'}) : JsonReply(200, {});
    }
    if (p.endsWith('/email-credentials/gmail') && method == 'DELETE') {
      return failDelete ? JsonReply(500, {'e': 'x'}) : JsonReply(200, {});
    }
    if (p.endsWith('/gmail/connect-url')) {
      return JsonReply(200, {'url': connectUrl});
    }
    return JsonReply(404, {'error': 'unknown $p'});
  }
}

const _launcherChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
];

List<MethodCall> _mockLauncher({bool result = true}) {
  final log = <MethodCall>[];
  for (final c in _launcherChannels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(c), (call) async {
      log.add(call);
      return result;
    });
  }
  return log;
}

Widget _wrap({Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(mockUser: MockUser()),
      child: const UspsTestScreen(),
    ),
  );
}

Future<JsonHttpOverrides> _pumpScreen(
  WidgetTester tester,
  _Backend backend,
) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final overrides = JsonHttpOverrides(backend.call);
  HttpOverrides.global = overrides;
  addTearDown(() => HttpOverrides.global = null);
  await tester.pumpWidget(_wrap());
  await _settle(tester);
  return overrides;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return null;
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDown(() {
    for (final c in _launcherChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), null);
    }
  });

  testWidgets('connected account loads digest with packages and mail',
      (tester) async {
    final launches = _mockLauncher();
    await _pumpScreen(tester, _Backend());

    expect(find.text('Disconnect Gmail'), findsOneWidget);
    expect(find.text('Packages'), findsOneWidget);
    expect(find.text('Mail Pieces'), findsOneWidget);
    expect(find.text('Acme Bank'), findsOneWidget);
    expect(find.text('Parcel Shop'), findsOneWidget);
    expect(find.textContaining('10/05/2026'), findsWidgets);

    // Package trailing button launches the tracking link.
    await tester.tap(find.byIcon(Icons.local_shipping).at(1));
    await _settle(tester);
    expect(launches, isNotEmpty);

    // Open the package detail dialog and use its Track button.
    await tester.tap(find.text('Parcel Shop'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('9400100000000000000000'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Track'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    // Second package (no sender) uses the primary action button.
    await tester.tap(find.text('9400200000000000000000').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Track Package'));
    await _settle(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('mail detail dialog shows dashboard and track actions',
      (tester) async {
    final launches = _mockLauncher();
    await _pumpScreen(tester, _Backend());

    await tester.tap(find.text('Acme Bank'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('View in USPS Dashboard'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Track Package'));
    await _settle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acme Bank'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View in USPS Dashboard'));
    await _settle(tester);
    await tester.pumpAndSettle();

    // A mail piece without a sender falls back to its subject; close it.
    await tester.tap(find.text('Flyer only'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    // Mail trailing button opens the dashboard link.
    await tester.tap(find.byIcon(Icons.open_in_new).first);
    await _settle(tester);
    expect(launches, isNotEmpty);
  });

  testWidgets('launch failure on both modes shows open-link error',
      (tester) async {
    _mockLauncher(result: false);
    await _pumpScreen(tester, _Backend());
    await tester.tap(find.byIcon(Icons.open_in_new).first);
    await _settle(tester);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('search shows results, opens details and clears back to today',
      (tester) async {
    _mockLauncher();
    await _pumpScreen(tester, _Backend());

    await tester.enterText(find.byType(TextField), 'parcel');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await _settle(tester);

    expect(find.text('Search Results'), findsOneWidget);
    expect(find.text('Search Parcel'), findsOneWidget);
    expect(find.text('Search summary'), findsOneWidget);

    await tester.tap(find.text('Search Parcel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search Sender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Trailing action on the first result.
    await tester.tap(find.byIcon(Icons.local_shipping).first);
    await _settle(tester);

    await tester.tap(find.text('Clear Search'));
    await _settle(tester);
    expect(find.text('Search Results'), findsNothing);
    expect(find.text('Packages'), findsOneWidget);
  });

  testWidgets('search with no matches offers to show today', (tester) async {
    await _pumpScreen(tester, _Backend(search: const []));
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.text("Show Today's Mail"), findsOneWidget);
    await tester.tap(find.text("Show Today's Mail"));
    await _settle(tester);
    expect(find.text('Packages'), findsOneWidget);
  });

  testWidgets('search failure shows the error card', (tester) async {
    await _pumpScreen(tester, _Backend(searchStatus: 500));
    await tester.enterText(find.byType(TextField), 'boom');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await _settle(tester);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('digest 204 shows not-found message', (tester) async {
    await _pumpScreen(tester, _Backend(digestStatus: 204));
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && w.style?.color == Colors.red),
      findsOneWidget,
    );
  });

  testWidgets('digest with no items shows the empty message', (tester) async {
    final backend = _Backend();
    final overrides = JsonHttpOverrides((m, u, b) {
      if (u.path.endsWith('/usps/latest')) {
        return JsonReply(200, {'mailpieces': [], 'packages': []});
      }
      return backend.call(m, u, b);
    });
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    HttpOverrides.global = overrides;
    addTearDown(() => HttpOverrides.global = null);
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(find.text('No items in digest'), findsWidgets);
  });

  testWidgets('clear cache success and failure show snackbars',
      (tester) async {
    final backend = _Backend();
    await _pumpScreen(tester, backend);
    await tester.tap(find.text('Clear Cache'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);

    backend.failClearCache = true;
    await tester.tap(find.text('Clear Cache'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsWidgets);
  });

  testWidgets('disconnect refreshes status and reports success',
      (tester) async {
    final backend = _Backend();
    await _pumpScreen(tester, backend);
    backend.status = {
      'connected': false,
      'status': 'NEEDS_RECONNECT',
      'message': 'Token expired',
    };
    await tester.tap(find.text('Disconnect Gmail'));
    await _settle(tester);
    expect(find.text('Token expired'), findsOneWidget);
    expect(find.text('Reconnect Google Account'), findsOneWidget);
  });

  testWidgets('disconnect failure shows error snackbar', (tester) async {
    await _pumpScreen(tester, _Backend(failDelete: true));
    await tester.tap(find.text('Disconnect Gmail'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('connect launches OAuth URL and rechecks on resume',
      (tester) async {
    final launches = _mockLauncher();
    final overrides = await _pumpScreen(
      tester,
      _Backend(status: const {'connected': false, 'status': 'DISCONNECTED'}),
    );
    expect(find.text('Connect Google Account'), findsOneWidget);
    await tester.tap(find.text('Connect Google Account'));
    await _settle(tester);
    expect(launches, isNotEmpty);

    final before = overrides.requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(overrides.requests.length, greaterThan(before));
  });

  testWidgets('connect falls back and reports when no launcher works',
      (tester) async {
    _mockLauncher(result: false);
    await _pumpScreen(
      tester,
      _Backend(
        status: const {'connected': false},
        connectUrl: 'https://accounts.example/oauth',
      ),
    );
    await tester.tap(find.text('Connect Google Account'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('connect with missing URL shows connect error',
      (tester) async {
    await _pumpScreen(
      tester,
      _Backend(connectUrl: null),
    );
    await tester.tap(find.text('Reconnect Google Account'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('status endpoint error marks Gmail disconnected',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    HttpOverrides.global =
        JsonHttpOverrides((m, u, b) => JsonReply(500, {'e': 'x'}));
    addTearDown(() => HttpOverrides.global = null);
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(find.text('Connect Google Account'), findsOneWidget);
  });

  testWidgets('status non-map body leaves Gmail disconnected',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    HttpOverrides.global =
        JsonHttpOverrides((m, u, b) => JsonReply(200, ['unexpected']));
    addTearDown(() => HttpOverrides.global = null);
    await tester.pumpWidget(_wrap());
    await _settle(tester);
    expect(find.text('Connect Google Account'), findsOneWidget);
  });
}
