import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/oracle_health_launch_uri.dart';

void main() {
  group('parseOracleHealthLaunchUri', () {
    const issuer = 'https://fhir-ehr-code.cerner.com/r4/test';

    test('rejects conflicting launch parameters', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=https%3A%2F%2Ftrusted.example.com%2Ffhir'
        '&launch=trusted-token'
        '#/oracle-health-launch'
        '?iss=https%3A%2F%2Funtrusted.example.com%2Ffhir'
        '&launch=other-token',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });

    test('parses standard query parameters', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=${Uri.encodeComponent(issuer)}'
        '&launch=temporary-token',
      );

      final result = parseOracleHealthLaunchUri(uri);

      expect(result?.issuer, issuer);
      expect(result?.launch, 'temporary-token');
    });

    test('parses Flutter Web hash-based query parameters', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '#/oracle-health-launch'
        '?iss=${Uri.encodeComponent(issuer)}'
        '&launch=temporary-token',
      );

      final result = parseOracleHealthLaunchUri(uri);

      expect(result?.issuer, issuer);
      expect(result?.launch, 'temporary-token');
    });

    test('rejects missing launch token', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=${Uri.encodeComponent(issuer)}',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });

    test('rejects missing issuer', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/?launch=temporary-token',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });

    test('rejects empty launch parameters', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=&launch=',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });

    test('rejects duplicate issuer parameters', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=https%3A%2F%2Ftrusted.example.com%2Ffhir'
        '&iss=https%3A%2F%2Funtrusted.example.com%2Ffhir'
        '&launch=temporary-token',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });

    test('rejects duplicate launch tokens', () {
      final uri = Uri.parse(
        'https://careconnect.example.com/'
        '?iss=https%3A%2F%2Ftrusted.example.com%2Ffhir'
        '&launch=first-token'
        '&launch=second-token',
      );

      expect(parseOracleHealthLaunchUri(uri), isNull);
    });
  });
}
