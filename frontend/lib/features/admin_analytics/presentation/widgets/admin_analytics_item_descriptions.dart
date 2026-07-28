/// Human-readable descriptions for admin analytics drill-down views.
class AdminAnalyticsItemDescriptions {
  const AdminAnalyticsItemDescriptions._();

  static const Map<String, String> _events = {
    'screen_view':
        'Recorded when a user navigates to a screen. Includes an anonymous screen identifier only.',
    'button_tap':
        'Recorded when a user taps an interactive control such as a button or menu item.',
    'feature_use':
        'Recorded when a user opens or engages with a product feature. The feature name is stored separately.',
    'session_start':
        'Marks the beginning of an anonymous app session, typically on cold start.',
    'session_end':
        'Marks the end of an anonymous app session, such as when the app is closed.',
    'sync_started':
        'Recorded when the offline sync queue begins processing queued API requests.',
    'sync_completed':
        'Recorded when an offline sync batch finishes successfully.',
    'sync_failed':
        'Recorded when an offline sync attempt fails before completing.',
    'error_network':
        'Recorded when a network-related failure is detected during an API call.',
    'error_timeout':
        'Recorded when an API request times out before receiving a response.',
    'offline_toggled':
        'Recorded when a user enables or disables offline mode from settings.',
    'privacy_telemetry_toggle':
        'Recorded when a user opts in or out of anonymous product telemetry.',
  };

  static const Map<String, String> _features = {
    'chat_room': 'Anonymous usage of the in-app chat room feature.',
    'medications_tracker': 'Anonymous usage of the medication tracker workflow.',
    'evv_start_visit': 'Anonymous usage of the EVV start-visit flow.',
    'video_call': 'Anonymous usage of the hybrid video call feature.',
    'dashboard': 'Anonymous usage of the main dashboard experience.',
    'tasks': 'Anonymous usage of the patient tasks area.',
  };

  static const Map<String, String> _errorEndpoints = {
    '/api/tasks': 'HTTP errors encountered while calling task-related API endpoints.',
    '/api/users': 'HTTP errors encountered while calling user account API endpoints.',
    '/api/patients': 'HTTP errors encountered while calling patient API endpoints.',
    '/api/messages': 'HTTP errors encountered while calling messaging API endpoints.',
  };

  static String event(String eventName) {
    return _events[eventName] ??
        'Anonymous telemetry event named "$eventName". No PII or PHI is included.';
  }

  static String feature(String featureName) {
    return _features[featureName] ??
        'Anonymous feature_use telemetry for "$featureName". Counts reflect how often users opened or engaged with this feature.';
  }

  static String errorEndpoint(String endpoint) {
    final key = endpoint.isEmpty ? 'unknown' : endpoint;
    return _errorEndpoints[key] ??
        'HTTP error telemetry grouped under endpoint bucket "$key". These are anonymous error counts, not request payloads.';
  }
}
