/// Extracts Oracle Health EHR launch parameters from an incoming URL.
///
/// Supports both standard query parameters and Flutter Web hash-based routes.
/// Rejects duplicate or conflicting launch parameters.
({String issuer, String launch})? parseOracleHealthLaunchUri(Uri uri) {
  final outerParameters = uri.queryParametersAll;

  final fragmentUri =
      uri.fragment.startsWith('/') ? Uri.tryParse(uri.fragment) : null;

  final fragmentParameters =
      fragmentUri?.queryParametersAll ?? const <String, List<String>>{};

  // Reject repeated parameters within either URL location.
  for (final key in ['iss', 'launch']) {
    if ((outerParameters[key]?.length ?? 0) > 1 ||
        (fragmentParameters[key]?.length ?? 0) > 1) {
      return null;
    }
  }

  // Never accept launch parameters from both locations.
  final outerHasLaunchParameters = outerParameters.containsKey('iss') ||
      outerParameters.containsKey('launch');

  final fragmentHasLaunchParameters = fragmentParameters.containsKey('iss') ||
      fragmentParameters.containsKey('launch');

  if (outerHasLaunchParameters && fragmentHasLaunchParameters) {
    return null;
  }

  final parameters =
      outerHasLaunchParameters ? outerParameters : fragmentParameters;

  final issuer = parameters['iss']?.single.trim();
  final launch = parameters['launch']?.single.trim();

  if (issuer == null || issuer.isEmpty || launch == null || launch.isEmpty) {
    return null;
  }

  return (issuer: issuer, launch: launch);
}
