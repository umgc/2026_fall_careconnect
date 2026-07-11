/// Created 2/19/2026: Team B
/// A security and data-integrity utility for sanitizing telemetry events.
///
/// The [TelemetryGuardrails] class acts as a hard filter to ensure that no
/// sensitive Personal Identifiable Information (PII) or Protected Health
/// Information (PHI) is transmitted off-device.
///
/// It enforces compliance with the application's "Offline-Only" policy for:
/// * **Symptom & Mood Tracking**
/// * **Medication Logging**
/// * **Electronic Visit Verification (EVV)**
class TelemetryGuardrails {
  /// The "Master Whitelist" of event names allowed to be tracked.
  static const Set<String> allowedEvents = {
    'privacy_telemetry_toggle',
    'screen_view',
    'button_tap',
    'error_network',
    'error_timeout',
    'offline_toggled',
    'feature_use',
    'sync_started',
    'sync_completed',
    'sync_failed',
    'session_start',
    'session_end',
    // Feature analytics (anonymous)
    'feature.medications.view_all',
    'feature.medications.view_active',
    'feature.medications.view_pending',
    'feature.medications.add',
    'feature.medications.approve',
    'feature.medications.delete_soft',
    'feature.medications.delete_hard',
  };

  /// A "Blacklist" of property keys that are never allowed to leave the device.
  static const Set<String> blockedKeys = {
    'name',
    'firstname',
    'lastname',
    'email',
    'phone',
    'address',
    'dob',
    'dateofbirth',
    'ssn',
    'mrn',
    'patientid',
    'providerid',
    'notes',
    'message',
    'symptom',
    'symptoms',
    'diagnosis',
    'medication',
    'freetext',
  };

  /// Validates and cleanses an event and its properties before transmission.
  ///
  /// This method performs the following checks:
  /// 1. **Event Whitelisting**: Drops the event if [eventName] is not in [allowedEvents].
  /// 2. **Key Filtering**: Removes any key found in [blockedKeys].
  /// 3. **Type Restriction**: Only allows primitives ([String], [num], [bool]).
  /// 4. **Length Heuristics**: Drops string values longer than 64 characters
  ///    to prevent "leakage" of free-text notes or descriptions.
  ///
  /// Returns a sanitized [Map] of properties, or `null` if the entire
  /// event should be discarded.
  static Map<String, Object?>? sanitize(
    String eventName,
    Map<String, Object?> props,
  ) {
    if (!allowedEvents.contains(eventName)) return null;

    final out = <String, Object?>{};

    for (final entry in props.entries) {
      final k = entry.key;

      // Case-insensitive check against the blocked keys list
      if (blockedKeys.contains(k.toLowerCase())) continue;

      final v = entry.value;
      if (v == null) continue;

      // Ensure data is a simple primitive and fits length constraints
      if (v is String || v is num || v is bool) {
        if (v is String && v.length > 64) continue; // blocks most free-text
        out[k] = v;
      }
    }
    return out;
  }
} // end class TelemetryGuardrails
