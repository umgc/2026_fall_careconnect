import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/pending_oracle_health_launch.dart';

void main() {
  setUp(PendingOracleHealthLaunch.clear);
  tearDown(PendingOracleHealthLaunch.clear);

  test('stores a valid Oracle Health launch', () {
    PendingOracleHealthLaunch.set(
      issuer: 'https://example.org/fhir',
      launch: 'temporary-launch-token',
    );

    expect(PendingOracleHealthLaunch.hasPending, isTrue);

    final result = PendingOracleHealthLaunch.take();

    expect(result, isNotNull);
    expect(result!.issuer, 'https://example.org/fhir');
    expect(result.launch, 'temporary-launch-token');
    expect(result.receivedAt.isUtc, isTrue);
  });

  test('consuming a launch clears pending information', () {
    PendingOracleHealthLaunch.set(
      issuer: 'https://example.org/fhir',
      launch: 'temporary-launch-token',
    );

    expect(PendingOracleHealthLaunch.take(), isNotNull);
    expect(PendingOracleHealthLaunch.hasPending, isFalse);
    expect(PendingOracleHealthLaunch.take(), isNull);
  });

  test('rejects empty launch parameters', () {
    expect(
      () => PendingOracleHealthLaunch.set(
        issuer: '',
        launch: 'temporary-launch-token',
      ),
      throwsArgumentError,
    );

    expect(
      () => PendingOracleHealthLaunch.set(
        issuer: 'https://example.org/fhir',
        launch: ' ',
      ),
      throwsArgumentError,
    );

    expect(PendingOracleHealthLaunch.hasPending, isFalse);
  });

  test('clears a pending launch', () {
    PendingOracleHealthLaunch.set(
      issuer: 'https://example.org/fhir',
      launch: 'temporary-launch-token',
    );

    PendingOracleHealthLaunch.clear();

    expect(PendingOracleHealthLaunch.hasPending, isFalse);
    expect(PendingOracleHealthLaunch.take(), isNull);
  });
}
