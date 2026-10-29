import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/oracle_health_issuer.dart';

void main() {
  const expectedIssuer = 'https://fhir-ehr-code.cerner.com/r4/example-tenant';

  group('Oracle Health issuer validation', () {
    test('accepts the configured issuer', () {
      expect(
        isTrustedOracleHealthIssuer(
          expectedIssuer,
          expectedIssuer: expectedIssuer,
        ),
        isTrue,
      );
    });

    test('rejects a different issuer', () {
      expect(
        isTrustedOracleHealthIssuer(
          'https://untrusted.example.com/r4/example-tenant',
          expectedIssuer: expectedIssuer,
        ),
        isFalse,
      );
    });

    test('rejects an insecure issuer', () {
      expect(
        isTrustedOracleHealthIssuer(
          'http://fhir-ehr-code.cerner.com/r4/example-tenant',
          expectedIssuer: expectedIssuer,
        ),
        isFalse,
      );
    });

    test('rejects an issuer with query parameters', () {
      expect(
        isTrustedOracleHealthIssuer(
          '$expectedIssuer?unexpected=true',
          expectedIssuer: expectedIssuer,
        ),
        isFalse,
      );
    });

    test('rejects a missing issuer', () {
      expect(
        isTrustedOracleHealthIssuer(
          '',
          expectedIssuer: expectedIssuer,
        ),
        isFalse,
      );
    });
  });
}
