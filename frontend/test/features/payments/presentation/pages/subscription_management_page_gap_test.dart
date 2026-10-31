// Gap coverage for SubscriptionManagementPage: the different shapes the
// subscription endpoint can return (a single object, a list with no active
// entry, customer id under different keys, an unexpected body). The page is
// rendered for real; the backend is a MockClient behind ApiService and
// payments use fakes only.
import 'dart:convert';

import 'package:care_connect_app/features/payments/presentation/pages/subscription_management_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus = MethodChannel(
  'dev.fluttercommunity.plus/connectivity_status',
);

final _plans = [
  for (final p in [
    ['1', 'Free Plan', 0],
    ['2', 'Standard Plan', 1999],
    ['3', 'Premium Plan', 2999],
  ])
    {
      'id': p[0],
      'priceId': p[0],
      'nickname': p[1],
      'amount': p[2],
      'interval': 'month',
      'active': true,
    },
];

const _names = {'1': 'Free Plan', '2': 'Standard Plan', '3': 'Premium Plan'};
const _prices = {'1': 0, '2': 1999, '3': 2999};

Map<String, Object?> _sub(String planId, {String customerKey = 'customer'}) => {
      'id': '1',
      'paymentSubscriptionId': 'sub_123',
      customerKey: 'cus_123',
      'status': 'active',
      'startedAt': '1700000000',
      'currentPeriodEnd': '1702592000',
      'planId': planId,
      'planName': _names[planId] ?? 'Legacy',
      'priceCents': _prices[planId] ?? 500,
    };

void main() {
  late Object? subscriptionBody;
  late int subscriptionStatus;
  late MockClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    subscriptionBody = [];
    subscriptionStatus = 200;
    client = MockClient((r) async {
      if (r.url.path.contains('/plans')) {
        return http.Response(jsonEncode(_plans), 200);
      }
      return http.Response(jsonEncode(subscriptionBody), subscriptionStatus);
    });
    ApiService.debugSetHttpClient(client);
    final session = jsonEncode({'id': 1, 'token': 'mock_token'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return session;
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
      _connectivity,
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SubscriptionManagementPage(),
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
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => client);
  }

  Finder switchButtons() =>
      find.widgetWithText(ElevatedButton, 'Switch to This Plan');
  Finder subscribeButtons() =>
      find.widgetWithText(ElevatedButton, 'Subscribe Now');

  testWidgets('a single subscription object marks that plan as current',
      (tester) async {
    subscriptionBody = _sub('3');

    await pumpPage(tester);

    expect(find.text('Premium Plan'), findsWidgets);
    expect(
      switchButtons(),
      findsNWidgets(2),
      reason: 'every plan except the current one offers a switch',
    );
    expect(subscribeButtons(), findsNothing);
  });

  testWidgets('a list with no active entry offers Subscribe Now',
      (tester) async {
    subscriptionBody = [
      {..._sub('2'), 'status': 'canceled'},
      'not a map',
    ];

    await pumpPage(tester);

    expect(subscribeButtons(), findsWidgets);
    expect(switchButtons(), findsNothing);
  });

  testWidgets('an unrecognised body is treated as no subscription',
      (tester) async {
    subscriptionBody = {'unexpected': true};

    await pumpPage(tester);

    expect(subscribeButtons(), findsWidgets);
    expect(switchButtons(), findsNothing);
  });

  testWidgets('a null body is treated as no subscription', (tester) async {
    subscriptionBody = null;

    await pumpPage(tester);

    expect(subscribeButtons(), findsWidgets);
  });

  for (final key in ['paymentCustomerId', 'customerId']) {
    testWidgets('an active subscription with $key still loads', (tester) async {
      subscriptionBody = [_sub('2', customerKey: key)];

      await pumpPage(tester);

      expect(switchButtons(), findsNWidgets(2));
      expect(subscribeButtons(), findsNothing);
    });
  }

  testWidgets('an active subscription pointing at an unknown plan falls back',
      (tester) async {
    subscriptionBody = [_sub('999')];

    await pumpPage(tester);

    expect(find.byType(SubscriptionManagementPage), findsOneWidget);
    expect(subscribeButtons(), findsNothing);
    expect(switchButtons(), findsWidgets);
  });
}
