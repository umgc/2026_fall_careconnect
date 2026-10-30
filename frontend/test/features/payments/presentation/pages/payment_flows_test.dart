// Flow tests for the payment pages
// (lib/features/payments/presentation/pages/): tier selection (free confirm
// and paid tiers), the web pay quote screen and the package list.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/payments/presentation/pages/select_package_page.dart';
import 'package:care_connect_app/features/payments/presentation/pages/subscription_tier_selection_page.dart';
import 'package:care_connect_app/features/payments/presentation/pages/web_pay_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

final _quote = {
  'tierId': 2,
  'tierName': 'Standard',
  'subtotalCents': 999,
  'taxCents': 80,
  'totalCents': 1079,
  'currency': 'USD',
  'taxRate': 0.08,
  'taxJurisdiction': 'CA',
};

class _Backend {
  int quoteStatus = 200;
  int payStatus = 200;
  int plansStatus = 200;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p.endsWith('/billing/quote')) {
      return http.Response(jsonEncode(_quote), quoteStatus);
    }
    if (p.contains('/billing/pay/')) {
      return http.Response('{"success":true}', payStatus);
    }
    if (p.endsWith('/subscriptions/plans')) {
      return http.Response(
        jsonEncode([
          {
            'id': '2',
            'active': true,
            'amount': 999,
            'interval': 'month',
            'nickname': 'Standard',
            'features': ['Feature A', 'Feature B'],
          },
          {
            'id': '3',
            'active': true,
            'amount': 29999,
            'interval': 'year',
            'nickname': 'Premium',
          },
          {'id': '9', 'active': false, 'nickname': 'Old'},
        ]),
        plansStatus,
      );
    }
    return http.Response('{}', 200);
  }
}

late _Backend _b;
String? _session;

Widget _routerApp(Widget home) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const Scaffold(body: Text('subscription page')),
      ),
      GoRoute(
        path: '/web-pay',
        builder: (_, state) =>
            Scaffold(body: Text('web pay ${(state.extra as Map)['tierId']}')),
      ),
      GoRoute(
        path: '/native-billing',
        builder: (_, state) => Scaffold(
            body: Text('native billing ${(state.extra as Map)['tierId']}')),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('home page')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: UserProvider()
      ..setUser(UserSession(
        id: 1,
        email: 'caregiver@test.com',
        role: 'caregiver',
        token: 'token',
        caregiverId: 1,
      )),
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      routerConfig: router,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester, Widget home, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await http.runWithClient(() async {
    await tester.pumpWidget(_routerApp(home));
    await _settle(tester);
  }, () => MockClient(_b.handle));
}

Future<void> _withHttp(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(_b.handle));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _b = _Backend();
    _session = null;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return _session;
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
    ApiService.debugSetHttpClient(MockClient(_b.handle));
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  group('SubscriptionTierSelectionPage', () {
    testWidgets('wide layout selects a paid tier and continues to web pay',
        (tester) async {
      await _pump(tester, const SubscriptionTierSelectionPage(
        email: 'a@b.com',
        userState: 'CA',
      ));
      expect(find.text('Most Popular'), findsOneWidget);
      expect(find.text('Video consultations'), findsOneWidget);

      await tester.tap(find.text('Premium'));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Continue to Payment'));
      await tester.pumpAndSettle();
      expect(find.text('web pay 3'), findsOneWidget);
    });

    testWidgets('narrow layout confirms the free plan', (tester) async {
      _session = jsonEncode({'id': 1, 'email': 'a@b.com', 'role': 'PATIENT'});
      await _pump(tester, const SubscriptionTierSelectionPage(),
          size: const Size(500, 3000));

      await tester.tap(find.text('Free'));
      await tester.pump();
      await tester.tap(find.text('Continue to Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Free Plan'), findsOneWidget);

      // Cancel first, then confirm.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(
          _b.calls.where((c) => c.endsWith('/subscriptions/create-by-user')),
          hasLength(1));
      expect(find.text('subscription page'), findsOneWidget);
    });

    testWidgets('free plan without a session still continues',
        (tester) async {
      await _pump(tester, const SubscriptionTierSelectionPage(),
          size: const Size(500, 3000));
      await tester.tap(find.text('Free'));
      await tester.pump();
      await tester.tap(find.text('Continue to Payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('subscription page'), findsOneWidget);
    });

    testWidgets('standard tier continues with tier id 2', (tester) async {
      await _pump(tester, const SubscriptionTierSelectionPage(),
          size: const Size(500, 3000));
      await tester.tap(find.text('Standard'));
      await tester.pump();
      await tester.tap(find.text('Continue to Payment'));
      await tester.pumpAndSettle();
      expect(find.text('web pay 2'), findsOneWidget);
    });
  });

  group('WebPayPage', () {
    testWidgets('shows the quote summary and refetches on state change',
        (tester) async {
      await _pump(tester, const WebPayPage(tierId: 2, userId: 5, state: 'NY'));
      expect(find.text('Order Summary'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('\$9.99'), findsOneWidget);
      expect(find.text('\$10.79'), findsOneWidget);
      expect(find.text('Currency: USD'), findsOneWidget);
      expect(find.text('Select Payment Method'), findsOneWidget);

      await _withHttp(() async {
        await tester.tap(find.text('NY'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TX').last);
        await tester.pumpAndSettle();
        await _settle(tester);
      });
      expect(
          _b.calls.where((c) => c.endsWith('/billing/quote')), hasLength(2));
    });

    testWidgets('quote error offers a retry', (tester) async {
      _b.quoteStatus = 401;
      await _pump(tester, const WebPayPage(tierId: 2));
      expect(find.textContaining('Error loading quote'), findsOneWidget);

      _b.quoteStatus = 500;
      await _withHttp(() async {
        await tester.tap(find.text('Retry'));
        await _settle(tester);
      });
      expect(find.textContaining('Failed to fetch billing quote'),
          findsOneWidget);
    });
  });

  group('SelectPackagePage', () {
    testWidgets('lists active plans in a grid and selects one',
        (tester) async {
      await _pump(tester, const SelectPackagePage(userId: '5'),
          size: const Size(1400, 2400));
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      expect(find.text('\$9.99'), findsOneWidget);
      expect(find.text('/year'), findsOneWidget);
      expect(find.text('Feature A'), findsOneWidget);

      await tester.tap(find.text('SELECT').first);
      await tester.pumpAndSettle();
      expect(find.text('native billing 2'), findsOneWidget);
    });

    testWidgets('medium and narrow layouts render the plans',
        (tester) async {
      await _pump(tester, const SelectPackagePage(),
          size: const Size(800, 2400));
      expect(find.text('Premium'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, const SelectPackagePage(),
          size: const Size(450, 2400));
      expect(find.text('Premium'), findsOneWidget);
    });

    testWidgets('error view retries and empty view explains', (tester) async {
      _b.plansStatus = 500;
      await _pump(tester, const SelectPackagePage());
      expect(find.textContaining('Failed to load subscription plans'),
          findsOneWidget);

      _b.plansStatus = 200;
      await _withHttp(() async {
        await tester.tap(find.text('Retry'));
        await _settle(tester);
      });
      expect(find.text('Premium'), findsOneWidget);
    });

    testWidgets('empty plan list shows the empty view', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(_routerApp(const SelectPackagePage()));
        await _settle(tester);
      }, () => MockClient((_) async => http.Response('[]', 200)));
      expect(find.text('No subscription plans available'), findsOneWidget);
    });

    testWidgets('network exception shows the error view', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(_routerApp(const SelectPackagePage()));
        await _settle(tester);
      }, () => MockClient((_) async => throw Exception('offline')));
      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });
}
