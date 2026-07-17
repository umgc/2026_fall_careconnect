import 'package:flutter/foundation.dart';

/// Risk level determines confirmation behavior for a voice intent.
/// - [low]: navigate immediately or with brief visual confirm
/// - [medium]: brief confirmation dialog before action
/// - [high]: detailed modal confirmation required before execution
enum IntentRiskLevel { low, medium, high }

/// A single registered voice intent with metadata and execution info.
class IntentRegistration {
  final String intentName;
  final String displayLabel;
  final IntentRiskLevel riskLevel;
  final bool requiresConfirmation;
  final String? routeDestination;
  final Future<void> Function(Map<String, String> entities)? handler;

  const IntentRegistration({
    required this.intentName,
    required this.displayLabel,
    this.riskLevel = IntentRiskLevel.low,
    this.requiresConfirmation = false,
    this.routeDestination,
    this.handler,
  });
}

/// App-wide singleton registry for voice intents.
///
/// Any team can register intents at startup or lazily. The voice command page
/// resolves recognized intents through this registry rather than hardcoded
/// switch statements.
///
/// Usage:
/// ```dart
/// VoiceIntentRegistry().register(IntentRegistration(
///   intentName: 'navigate_home',
///   displayLabel: 'Home',
///   routeDestination: '/dashboard',
///   requiresConfirmation: true,
/// ));
/// ```
class VoiceIntentRegistry {
  static final VoiceIntentRegistry _instance = VoiceIntentRegistry._internal();
  factory VoiceIntentRegistry() => _instance;
  VoiceIntentRegistry._internal();

  final Map<String, IntentRegistration> _registry = {};

  /// Register a single intent. Overwrites if the same intentName exists.
  void register(IntentRegistration intent) {
    _registry[intent.intentName] = intent;
  }

  /// Register multiple intents at once.
  void registerAll(List<IntentRegistration> intents) {
    for (final intent in intents) {
      _registry[intent.intentName] = intent;
    }
  }

  /// Look up an intent by name. Returns null if not registered.
  IntentRegistration? lookup(String intentName) {
    return _registry[intentName];
  }

  /// Look up an intent by its route destination. Returns null if none match.
  IntentRegistration? lookupByRoute(String route) {
    for (final entry in _registry.values) {
      if (entry.routeDestination == route) return entry;
    }
    return null;
  }

  /// All currently registered intents.
  List<IntentRegistration> get allIntents =>
      List.unmodifiable(_registry.values);

  /// Whether the registry has any intents registered.
  bool get isEmpty => _registry.isEmpty;

  /// Number of registered intents.
  int get length => _registry.length;

  /// Clear registry. Exposed for test isolation.
  @visibleForTesting
  void clear() {
    _registry.clear();
  }
}

/// Registers the default set of voice intents for the app.
/// Call once at app startup or lazily on first voice page open.
void registerDefaultVoiceIntents() {
  final registry = VoiceIntentRegistry();
  if (registry.isEmpty) {
    registry.registerAll(_defaultIntents);
  }
}

const _defaultIntents = [
  // --- Generic navigate (AI returns destination dynamically) ---
  IntentRegistration(
    intentName: 'navigate',
    displayLabel: 'Navigate',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
  ),

  // --- Core navigation (Patient & Caregiver) ---
  IntentRegistration(
    intentName: 'navigate_home',
    displayLabel: 'Home',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/dashboard',
  ),
  IntentRegistration(
    intentName: 'navigate_dashboard',
    displayLabel: 'Dashboard',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/dashboard',
  ),
  IntentRegistration(
    intentName: 'navigate_calendar',
    displayLabel: 'Calendar',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/calendar',
  ),
  IntentRegistration(
    intentName: 'navigate_messages',
    displayLabel: 'Messages',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/dashboard?tab=messages',
  ),
  IntentRegistration(
    intentName: 'navigate_profile',
    displayLabel: 'Profile',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/profile',
  ),
  IntentRegistration(
    intentName: 'navigate_settings',
    displayLabel: 'Settings',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/settings',
  ),
  IntentRegistration(
    intentName: 'navigate_menu',
    displayLabel: 'Menu',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/dashboard?tab=menu',
  ),

  // --- Health & Wellness ---
  IntentRegistration(
    intentName: 'navigate_symptoms',
    displayLabel: 'Symptom Tracker',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/symptoms',
  ),
  IntentRegistration(
    intentName: 'navigate_medication',
    displayLabel: 'Medication Tracker',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/medication',
  ),
  IntentRegistration(
    intentName: 'navigate_virtual_checkin',
    displayLabel: 'Virtual Check-In',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/virtual-checkin',
  ),

  // --- Integrations & Devices ---
  IntentRegistration(
    intentName: 'navigate_wearables',
    displayLabel: 'Wearables',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/wearables',
  ),
  IntentRegistration(
    intentName: 'navigate_home_monitoring',
    displayLabel: 'Home Monitoring',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/home-monitoring',
  ),
  IntentRegistration(
    intentName: 'navigate_smart_devices',
    displayLabel: 'Smart Devices',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/smart-devices',
  ),

  // --- Social & Communication ---
  IntentRegistration(
    intentName: 'navigate_social_feed',
    displayLabel: 'Social Feed',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/social-feed',
  ),

  // --- Caregiver-specific ---
  IntentRegistration(
    intentName: 'navigate_patient_list',
    displayLabel: 'Patient List',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/tasks',
  ),
  IntentRegistration(
    intentName: 'navigate_evv',
    displayLabel: 'EVV Dashboard',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/evv',
  ),
  IntentRegistration(
    intentName: 'navigate_notetaker',
    displayLabel: 'Medical Notetaker',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/notetaker-search',
  ),
  IntentRegistration(
    intentName: 'navigate_invoice',
    displayLabel: 'Invoice Assistant',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/invoice-assistant',
  ),

  // --- Files & Documents ---
  IntentRegistration(
    intentName: 'navigate_files',
    displayLabel: 'File Management',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/file-management',
  ),
  IntentRegistration(
    intentName: 'navigate_informed_delivery',
    displayLabel: 'Informed Delivery',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/informed-delivery',
  ),

  // --- Gamification ---
  IntentRegistration(
    intentName: 'navigate_gamification',
    displayLabel: 'Gamification',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/gamification',
  ),

  // --- Configuration & AI ---
  IntentRegistration(
    intentName: 'navigate_ai_config',
    displayLabel: 'AI Configuration',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/ai-configuration',
  ),
  IntentRegistration(
    intentName: 'navigate_notetaker_config',
    displayLabel: 'Notetaker Configuration',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/notetaker-configuration',
  ),

  // --- Payments & Subscription ---
  IntentRegistration(
    intentName: 'navigate_subscription',
    displayLabel: 'Subscription',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/subscription',
  ),

  // --- Search ---
  IntentRegistration(
    intentName: 'navigate_search',
    displayLabel: 'Search',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/search',
  ),

  // --- Voice ---
  IntentRegistration(
    intentName: 'navigate_voice',
    displayLabel: 'Voice Commands',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: false,
    routeDestination: '/voice',
  ),

  // --- Action intents (non-navigation, require confirmation) ---
  IntentRegistration(
    intentName: 'call',
    displayLabel: 'Call Contact',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'schedule',
    displayLabel: 'Schedule Appointment',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'sos',
    displayLabel: 'SOS Emergency Alert',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'start_video_call',
    displayLabel: 'Start Video Call',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'log_symptom',
    displayLabel: 'Log Symptom',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'log_medication',
    displayLabel: 'Log Medication',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'send_message',
    displayLabel: 'Send Message',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
  ),
  IntentRegistration(
    intentName: 'check_in',
    displayLabel: 'Start Check-In',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
  ),
];
