import 'env_constant.dart' as env;

/// Global app configuration for environment variables and settings
class AppConfig {
  /// Google Places API Key for address autocomplete
  static String getGooglePlacesApiKey() {
    return env.getGooglePlacesApiKey();
  }

  /// Backend base URL
  static String getBackendBaseUrl() {
    return env.getBackendBaseUrl();
  }

  /// Apple Merchant ID for Apple Pay
  static String getAppleMerchantId() {
    return env.getAppleMerchantId();
  }

  /// Google Pay Merchant ID
  static String getGooglePayMerchantId() {
    return env.getGooglePayMerchantId();
  }

  /// Check if Google Places API key is configured
  static bool isGooglePlacesConfigured() {
    return getGooglePlacesApiKey().isNotEmpty;
  }
}
