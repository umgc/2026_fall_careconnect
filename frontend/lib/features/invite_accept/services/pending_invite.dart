/// Holds an invite token that must survive the multi-screen auth flow
/// (issue #75, acceptance criterion: "Success and failure states remain visible
/// and persist across redirects").
///
/// When an unauthenticated user opens an invite link, we stash the token here,
/// send them through sign-up or login, and consume it once they're
/// authenticated. In-memory is sufficient: the handoff happens within a single
/// app session. It is deliberately simple and has no external dependencies so
/// it is trivial to unit-test.
class PendingInvite {
  PendingInvite._();

  static String? _token;

  /// Stash the invite token before redirecting to sign-up / login.
  static void set(String token) {
    _token = token;
  }

  /// The stashed token, if any.
  static String? get token => _token;

  /// Whether an invite is waiting to be accepted after authentication.
  static bool get hasPending => _token != null && _token!.isNotEmpty;

  /// Consume and clear the stashed token (call right before accepting).
  static String? take() {
    final t = _token;
    _token = null;
    return t;
  }

  /// Clear without consuming (e.g. user abandoned the flow).
  static void clear() {
    _token = null;
  }
}
