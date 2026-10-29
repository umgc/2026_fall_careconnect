/// Checks whether an incoming SMART launch issuer matches the
/// configured Oracle Health FHIR issuer.
bool isTrustedOracleHealthIssuer(
  String issuer, {
  required String expectedIssuer,
}) {
  final incoming = Uri.tryParse(issuer);
  final expected = Uri.tryParse(expectedIssuer);

  if (incoming == null || expected == null) {
    return false;
  }

  if (incoming.scheme != 'https' || expected.scheme != 'https') {
    return false;
  }

  if (incoming.host.isEmpty || expected.host.isEmpty) {
    return false;
  }

  if (incoming.userInfo.isNotEmpty ||
      expected.userInfo.isNotEmpty ||
      incoming.hasQuery ||
      expected.hasQuery ||
      incoming.hasFragment ||
      expected.hasFragment) {
    return false;
  }

  return incoming == expected;
}
