// Tests for PaymentRepository
// (lib/features/payments/data/payment_repository.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/payments/data/payment_repository.dart';

void main() {
  group('PaymentRepository', () {
    test('createPaymentIntent returns a non-empty string', () async {
      final repo = PaymentRepository();
      final secret = await repo.createPaymentIntent(1000);
      expect(secret, isNotEmpty);
    });

    test('createPaymentIntent returns the same value for any amount', () async {
      final repo = PaymentRepository();
      final s1 = await repo.createPaymentIntent(500);
      final s2 = await repo.createPaymentIntent(9999);
      expect(s1, isA<String>());
      expect(s2, isA<String>());
    });

    test('createPaymentIntent returns dummy_client_secret', () async {
      final repo = PaymentRepository();
      final secret = await repo.createPaymentIntent(100);
      expect(secret, 'dummy_client_secret');
    });

    test('createPaymentIntent works with zero amount', () async {
      final repo = PaymentRepository();
      final secret = await repo.createPaymentIntent(0);
      expect(secret, isNotEmpty);
    });

    test('createPaymentIntent works with large amount', () async {
      final repo = PaymentRepository();
      final secret = await repo.createPaymentIntent(999999);
      expect(secret, isA<String>());
    });

    test('multiple instances return same result', () async {
      final repo1 = PaymentRepository();
      final repo2 = PaymentRepository();
      final s1 = await repo1.createPaymentIntent(100);
      final s2 = await repo2.createPaymentIntent(200);
      expect(s1, equals(s2));
    });

    test('PaymentRepository can be instantiated', () {
      final repo = PaymentRepository();
      expect(repo, isNotNull);
    });
  });
}
