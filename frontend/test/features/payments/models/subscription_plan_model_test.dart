// Tests for SubscriptionPlan model
// (lib/features/payments/models/subscription_plan_model.dart).
// Pure-Dart model with fromJson, toJson, and computed getters.

import 'package:care_connect_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/payments/models/subscription_plan_model.dart';

void main() {
  group('SubscriptionPlan.fromJson', () {
    test('parses all fields when fully populated', () {
      // Verifies the happy-path where every JSON key is present.
      final plan = SubscriptionPlan.fromJson({
        'id': 'plan_abc123',
        'active': true,
        'amount': 1999,
        'currency': 'usd',
        'interval': 'month',
        'intervalCount': 1,
        'product': 'prod_xyz',
        'nickname': 'Standard Plan',
        'description': 'A great plan',
        'features': ['Feature A', 'Feature B'],
      });

      expect(plan.id, 'plan_abc123');
      expect(plan.active, isTrue);
      expect(plan.amount, 1999);
      expect(plan.currency, 'usd');
      expect(plan.interval, 'month');
      expect(plan.intervalCount, 1);
      expect(plan.product, 'prod_xyz');
      expect(plan.nickname, 'Standard Plan');
      expect(plan.customDescription, 'A great plan');
      expect(plan.features, ['Feature A', 'Feature B']);
    });

    test('uses defaults when JSON fields are absent', () {
      // Verifies the ?? fallback values used by fromJson.
      final plan = SubscriptionPlan.fromJson({});

      expect(plan.id, '');
      expect(plan.active, isFalse);
      expect(plan.amount, 0);
      expect(plan.currency, 'usd');
      expect(plan.interval, 'month');
      expect(plan.intervalCount, 1);
      expect(plan.product, '');
      expect(plan.nickname, '');
      expect(plan.customDescription, isNull);
      expect(plan.features, isEmpty);
    });

    test('features is empty list when features key is null', () {
      // Verifies that null features key produces an empty list.
      final plan = SubscriptionPlan.fromJson({'features': null});
      expect(plan.features, isEmpty);
    });
  });

  group('SubscriptionPlan.toJson', () {
    test('serializes all required fields', () {
      // Verifies that toJson output contains the expected keys and values.
      final plan = SubscriptionPlan(
        id: 'plan_test',
        active: true,
        amount: 2999,
        currency: 'usd',
        interval: 'year',
        intervalCount: 1,
        product: 'prod_test',
        nickname: 'Premium Plan',
      );
      final json = plan.toJson();

      expect(json['id'], 'plan_test');
      expect(json['active'], isTrue);
      expect(json['amount'], 2999);
      expect(json['currency'], 'usd');
      expect(json['interval'], 'year');
      expect(json['intervalCount'], 1);
      expect(json['product'], 'prod_test');
      expect(json['nickname'], 'Premium Plan');
    });
  });

  group('SubscriptionPlan.formattedPrice', () {
    test('formats cents to dollars with two decimal places', () {
      // 1999 cents → $19.99
      final plan = SubscriptionPlan(
        id: 'p1', active: true, amount: 1999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr', nickname: 'N',
      );
      expect(plan.formattedPrice, '\$19.99');
    });

    test('formats zero amount correctly', () {
      final plan = SubscriptionPlan(
        id: 'p2', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr', nickname: 'N',
      );
      expect(plan.formattedPrice, '\$0.00');
    });
  });

  group('SubscriptionPlan.description', () {
    testWidgets('returns customDescription when set', (tester) async {
      // Verifies the customDescription takes precedence.
      final plan = SubscriptionPlan(
        id: 'p1', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr',
        nickname: 'Standard Plan', customDescription: 'My custom description',
      );
      final t = AppLocalizationsEn();

      expect(plan.description(t), 'My custom description');
    });

    test('returns standard description for standard nickname', () {
      // Verifies the "standard" keyword triggers the appropriate copy.
      final plan = SubscriptionPlan(
        id: 'p1', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr',
        nickname: 'Standard Plan',
      );
      final t = AppLocalizationsEn();

      expect(plan.description(t), contains('Basic features'));
    });

    test('returns premium description for premium nickname', () {
      // Verifies the "premium" keyword triggers the appropriate copy.
      final plan = SubscriptionPlan(
        id: 'p1', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr',
        nickname: 'Premium Plan',
      );
      final t = AppLocalizationsEn();

      expect(plan.description(t), contains('video calls'));
    });

    test('returns default description for unrecognized nickname', () {
      // Verifies the fallback description for unknown plan names.
      final plan = SubscriptionPlan(
        id: 'p1', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr',
        nickname: 'Enterprise XL',
      );
      final t = AppLocalizationsEn();

      expect(plan.description(t), contains('CareConnect services'));
    });
  });

  group('SubscriptionPlan.formattedInterval', () {
    test('returns yearly for year interval', () {
      final plan = SubscriptionPlan(
        id: 'p', active: true, amount: 0, currency: 'usd',
        interval: 'year', intervalCount: 1, product: 'pr', nickname: 'N',
      );
      final t = AppLocalizationsEn();

      expect(plan.formattedInterval(t), 'yearly');
    });

    test('returns monthly for month interval', () {
      final plan = SubscriptionPlan(
        id: 'p', active: true, amount: 0, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'pr', nickname: 'N',
      );
      final t = AppLocalizationsEn();

      expect(plan.formattedInterval(t), 'monthly');
    });
  });
}
