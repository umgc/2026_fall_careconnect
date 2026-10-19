import 'package:connectivity_plus/connectivity_plus.dart';

/// Handles routing between online and offline execution paths.
///
/// Responsibilities:
/// - Detect current connectivity state
/// - Route execution to online or offline handlers
/// - Optionally fall back to offline if online execution fails due to network issues
///
/// NOTE:
/// This service does NOT modify business logic. It only determines which
/// execution path should be used.
class ConnectivityRouterService {
  ConnectivityRouterService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Routes execution based on connectivity status.
  ///
  /// - If offline → executes [offline]
  /// - If online → executes [online]
  /// - If online fails and fallback is enabled → executes [offline]
  Future<T> route<T>({
    required Future<T> Function() online,
    required Future<T> Function() offline,
    bool fallbackToOfflineOnOnlineError = false,
  }) async {
    final currentlyOnline = await _isCurrentlyOnline();

    assert(() {
      print(
          '[Connectivity] Current state: ${currentlyOnline ? "ONLINE" : "OFFLINE"}');
      return true;
    }());

    if (!currentlyOnline) {
      assert(() {
        print('[Connectivity] Routing to OFFLINE handler');
        return true;
      }());
      return offline();
    }

    try {
      final result = await online();

      assert(() {
        print('[Connectivity] Online execution succeeded');
        return true;
      }());

      return result;
    } catch (error) {
      assert(() {
        print('[Connectivity] Online execution failed: $error');
        return true;
      }());

      if (fallbackToOfflineOnOnlineError && _isLikelyNetworkFailure(error)) {
        assert(() {
          print(
              '[Connectivity] Falling back to OFFLINE handler due to online error');
          return true;
        }());
        return offline();
      }

      rethrow;
    }
  }

  /// Checks whether the device is currently connected to a network.
  Future<bool> _isCurrentlyOnline() async {
    final result = await _connectivity.checkConnectivity();

    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }

    return result.any((entry) => entry != ConnectivityResult.none);
  }

  /// Determines whether an error is likely caused by network failure.
  bool _isLikelyNetworkFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('timed out');
  }
}
