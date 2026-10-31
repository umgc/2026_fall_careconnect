// Tests for NativeBillingService
// (lib/features/payments/services/native_billing_service.dart) against an
// in-memory in-app-purchase platform and a MockClient for server
// verification.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:care_connect_app/features/payments/services/native_billing_service.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

class _FakeIap extends InAppPurchasePlatform with MockPlatformInterfaceMixin {
  final StreamController<List<PurchaseDetails>> stream =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  bool found = true;
  final List<String> bought = <String>[];
  final List<String> completed = <String>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
      Set<String> identifiers) async {
    return ProductDetailsResponse(
      productDetails: found
          ? [
              ProductDetails(
                id: identifiers.first,
                title: 'Plan',
                description: 'Plan',
                price: '\$9.99',
                rawPrice: 9.99,
                currencyCode: 'USD',
              ),
            ]
          : const [],
      notFoundIDs: found ? const [] : identifiers.toList(),
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam.productDetails.id);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.productID);
  }
}

PurchaseDetails _purchase(String id, PurchaseStatus status,
        {bool pending = false}) =>
    PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server-token',
        source: 'google_play',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = pending;

/// Lets stream listeners and the async verification run.
Future<void> _drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeIap iap;
  late AppLocalizations t;
  late List<String> successes;
  late List<String> errors;
  late NativeBillingService service;
  // Server verification runs in the zone the purchase stream was listened
  // in, so the service is initialised inside http.runWithClient and the
  // response is chosen per test through this handler.
  late Future<http.Response> Function(http.Request) server;

  setUpAll(() {
    // Create the InAppPurchase singleton without registering a real store
    // platform, so the fake set in setUp is the one used.
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    server = (_) async => http.Response('{}', 200);
    iap = _FakeIap();
    InAppPurchasePlatform.instance = iap;
    t = lookupAppLocalizations(const Locale('en'));
    successes = <String>[];
    errors = <String>[];
    service = NativeBillingService(
      userId: 5,
      t: t,
      onPurchaseSuccess: () => successes.add('ok'),
      onPurchaseError: errors.add,
    );
    http.runWithClient(service.init, () => MockClient((r) => server(r)));
  });

  tearDown(() async {
    await service.dispose();
    await iap.stream.close();
  });

  test('buySubscription buys the queried product', () async {
    await service.buySubscription('standard_monthly', userId: 5);
    expect(iap.bought, ['standard_monthly']);
  });

  test('buySubscription fails when the store is unavailable', () async {
    iap.available = false;
    await expectLater(
      service.buySubscription('standard_monthly', userId: 5),
      throwsA(isA<Exception>()),
    );
  });

  test('buySubscription fails when the product is not found', () async {
    iap.found = false;
    await expectLater(
      service.buySubscription('premium_monthly', userId: 5),
      throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('premium_monthly'))),
    );
  });

  test('purchased update is verified, completed and reported', () async {
    final requests = <http.Request>[];
    server = (r) async {
      requests.add(r);
      return http.Response('{}', 200);
    };
    iap.stream.add([
      _purchase('premium_monthly', PurchaseStatus.purchased, pending: true),
    ]);
    await _drain();
    expect(requests.single.url.path, '/v1/api/billing/pay/google');
    expect(requests.single.body, contains('"tierId":3'));
    expect(iap.completed, ['premium_monthly']);
    expect(successes, hasLength(1));
  });

  test('restored update with unknown product uses the default tier',
      () async {
    final bodies = <String>[];
    server = (r) async {
      bodies.add(r.body);
      return http.Response('{}', 200);
    };
    iap.stream.add([_purchase('mystery', PurchaseStatus.restored)]);
    await _drain();
    expect(bodies.single, contains('"tierId":2'));
    expect(iap.completed, isEmpty);
    expect(successes, hasLength(1));
  });

  test('failed server verification reports an error', () async {
    server = (r) async => http.Response('nope', 500);
    iap.stream.add([_purchase('free_monthly', PurchaseStatus.purchased)]);
    await _drain();
    expect(successes, isEmpty);
    expect(errors.single, contains('nope'));
  });

  test('error update reports the purchase failure', () async {
    iap.stream.add([_purchase('standard_monthly', PurchaseStatus.error)]);
    await _drain();
    expect(errors.single, t.nativebilling_purchaseFailed);
  });

  test('stream errors are forwarded', () async {
    iap.stream.addError(StateError('store down'));
    await _drain();
    expect(errors.single, contains('store down'));
  });
}
