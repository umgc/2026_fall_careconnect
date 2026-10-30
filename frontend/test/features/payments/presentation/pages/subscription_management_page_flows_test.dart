// Navigation flows for SubscriptionManagementPage
// (lib/features/payments/presentation/pages/subscription_management_page.dart)
// under a GoRouter: switching plans (confirm, cancel failure), subscribing
// with no active plan, the free-plan confirmation, and cancelling a
// subscription through both confirmation dialogs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/payments/presentation/pages/subscription_management_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

final _plans = [
  {
    'id': '1',
    'priceId': '1',
    'nickname': 'Free Plan',
    'amount': 0,
    'interval': 'month',
    'active': true,
  },
  {
    'id': '2',
    'priceId': '2',
    'nickname': 'Standard Plan',
    'amount': 1999,
    'interval': 'month',
    'active': true,
  },
  {
    'id': '3',
    'priceId': '3',
    'nickname': 'Premium Plan',
    'amount': 2999,
    'interval': 'month',
    'active': true,
  },
];

final _activeSub = [
  {
    'id': '1',
    'paymentSubscriptionId': 'sub_123',
    'customer': 'cus_123',
    'status': 'active',
    'startedAt': '1700000000',
    'currentPeriodEnd': '1702592000',
    'planId': '2',
    'planName': 'Standard Plan',
    'priceCents': 1999,
  },
];

class _Backend {
  int subscriptionStatus = 200;
  Object? subscriptionBody = _activeSub;
  int cancelStatus = 200;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p.contains('/plans')) return http.Response(jsonEncode(_plans), 200);
    if (p.contains('/cancel')) {
      return http.Response(
        cancelStatus == 200 ? '{"message":"ok"}' : '{"error":"cannot cancel"}',
        cancelStatus,
      );
    }
    if (p.contains('/create-by-user')) return http.Response('{}', 200);
    return http.Response(jsonEncode(subscriptionBody), subscriptionStatus);
  }
}

late _Backend _b;
late MockClient _client;

Future<void> _settle(WidgetTester tester, [int n = 10]) async {
  await http.runWithClient(() async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => _client);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const SubscriptionManagementPage(),
      ),
      for (final path in ['/native-billing', '/web-pay', '/login', '/home'])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route $path')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await http.runWithClient(() async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(),
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
  }, () => _client);
  await _settle(tester, 20);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _b = _Backend();
    _client = MockClient(_b.handle);
    ApiService.debugSetHttpClient(_client);
    final session = jsonEncode({'id': 1, 'token': 'mock_token'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return session;
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  Future<void> pressSwitch(WidgetTester tester, int index) async {
    final buttons =
        find.widgetWithText(ElevatedButton, 'Switch to This Plan');
    await tester.ensureVisible(buttons.at(index));
    await tester.pump();
    tester.widget<ElevatedButton>(buttons.at(index)).onPressed!();
    await tester.pumpAndSettle();
  }

  testWidgets('confirming a plan change cancels and opens checkout',
      (tester) async {
    await _pump(tester);
    expect(find.text('Switch to This Plan'), findsWidgets);

    await pressSwitch(tester, 1); // Premium
    expect(find.text('CONFIRM CHANGE'), findsOneWidget);
    await tester.tap(find.text('CONFIRM CHANGE'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(_b.calls.where((c) => c.contains('/cancel')), hasLength(1));
    expect(find.text('route /native-billing'), findsOneWidget);
  });

  testWidgets('a failed cancel during plan change shows the error',
      (tester) async {
    _b.cancelStatus = 500;
    await _pump(tester);
    await pressSwitch(tester, 1);
    await tester.tap(find.text('CONFIRM CHANGE'));
    await _settle(tester);
    expect(find.textContaining('cannot cancel'), findsOneWidget);
  });

  testWidgets('switching to the free plan asks for confirmation',
      (tester) async {
    await _pump(tester);
    await pressSwitch(tester, 0); // Free
    await tester.tap(find.text('CONFIRM CHANGE'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Confirm Free Plan'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await _settle(tester, 12);
    expect(_b.calls.where((c) => c.contains('/create-by-user')), hasLength(1));
  });

  testWidgets('without a subscription Subscribe Now opens checkout',
      (tester) async {
    _b.subscriptionStatus = 404;
    _b.subscriptionBody = {'error': 'none'};
    await _pump(tester);

    final subscribe = find.widgetWithText(ElevatedButton, 'Subscribe Now');
    await tester.ensureVisible(subscribe.last);
    await tester.pump();
    tester.widget<ElevatedButton>(subscribe.last).onPressed!();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('route /native-billing'), findsOneWidget);
  });

  testWidgets('free plan dialog can be dismissed', (tester) async {
    _b.subscriptionStatus = 404;
    _b.subscriptionBody = {'error': 'none'};
    await _pump(tester);
    final subscribe = find.widgetWithText(ElevatedButton, 'Subscribe Now');
    await tester.ensureVisible(subscribe.first);
    await tester.pump();
    tester.widget<ElevatedButton>(subscribe.first).onPressed!();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Confirm Free Plan'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Free Plan'), findsNothing);
  });

  testWidgets('cancelling the subscription logs out after two confirms',
      (tester) async {
    await _pump(tester);
    final cancel = find.text('Cancel Subscription');
    await tester.ensureVisible(cancel.first);
    await tester.tap(cancel.first);
    await tester.pumpAndSettle();

    // First "keep my plan" backs out.
    await tester.tap(find.text('NO, KEEP MY PLAN'));
    await tester.pumpAndSettle();

    await tester.tap(cancel.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, CANCEL'));
    await tester.pumpAndSettle();
    expect(find.text('Final Confirmation'), findsOneWidget);
    await tester.tap(find.text('NO, GO BACK'));
    await tester.pumpAndSettle();

    await tester.tap(cancel.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, CANCEL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, CANCEL MY SUBSCRIPTION'));
    await _settle(tester, 15);
    await tester.pumpAndSettle();
    expect(find.text('route /login'), findsOneWidget);
  });

  testWidgets('cancel failure shows the error and stays', (tester) async {
    _b.cancelStatus = 500;
    await _pump(tester);
    final cancel = find.text('Cancel Subscription');
    await tester.ensureVisible(cancel.first);
    await tester.tap(cancel.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, CANCEL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, CANCEL MY SUBSCRIPTION'));
    await _settle(tester);
    expect(find.textContaining('cannot cancel'), findsOneWidget);
  });

  testWidgets('back arrow goes home', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('route /home'), findsOneWidget);
  });
}
