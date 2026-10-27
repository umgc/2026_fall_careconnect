class PendingOracleHealthLaunch {
  PendingOracleHealthLaunch._();

  static String? _issuer;
  static String? _launch;
  static DateTime? _receivedAt;

  static bool get hasPending =>
      _issuer != null &&
      _issuer!.isNotEmpty &&
      _launch != null &&
      _launch!.isNotEmpty;

  static void set({
    required String issuer,
    required String launch,
  }) {
    if (issuer.trim().isEmpty || launch.trim().isEmpty) {
      throw ArgumentError('Oracle Health launch parameters are required.');
    }

    _issuer = issuer;
    _launch = launch;
    _receivedAt = DateTime.now().toUtc();
  }

  static ({String issuer, String launch, DateTime receivedAt})? take() {
    if (!hasPending) return null;

    final result = (
      issuer: _issuer!,
      launch: _launch!,
      receivedAt: _receivedAt!,
    );

    clear();
    return result;
  }

  static void clear() {
    _issuer = null;
    _launch = null;
    _receivedAt = null;
  }
}
