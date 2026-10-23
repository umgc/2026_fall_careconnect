import 'env_constant.dart';

class EnvironmentConfig {
  /// Call this anywhere you need the API base.
  static String get baseUrl {
    return getBackendBaseUrl();
  }
}
