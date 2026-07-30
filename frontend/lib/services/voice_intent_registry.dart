import 'package:flutter/foundation.dart';

/// Risk level determines confirmation behavior for a voice intent.
/// - [low]: navigate immediately or with brief visual confirm
/// - [medium]: brief confirmation dialog before action
/// - [high]: detailed modal confirmation required before execution
enum IntentRiskLevel { low, medium, high }

/// Defines a voice intent (verb) with metadata about how it should be handled.
class IntentDefinition {
  final String intentName;
  final String displayLabel;
  final IntentRiskLevel riskLevel;
  final bool requiresConfirmation;
  final String? entityKey;
  final Future<void> Function(Map<String, String> entities)? handler;

  const IntentDefinition({
    required this.intentName,
    required this.displayLabel,
    this.riskLevel = IntentRiskLevel.low,
    this.requiresConfirmation = false,
    this.entityKey,
    this.handler,
  });
}

/// A navigation destination that can be reached via the "navigate" intent.
class NavigationDestination {
  final String name;
  final String route;
  final String displayLabel;

  const NavigationDestination({
    required this.name,
    required this.route,
    required this.displayLabel,
  });
}

/// App-wide singleton registry for voice intents using an intent + entity model.
///
/// Intents are verbs (navigate, call, schedule). Entities are nouns resolved
/// per-intent (destination for navigate, contact for call, etc.).
///
/// Usage:
/// ```dart
/// final registry = VoiceIntentRegistry();
/// registry.registerIntent(IntentDefinition(
///   intentName: 'navigate',
///   displayLabel: 'Navigate',
///   entityKey: 'destination',
///   requiresConfirmation: true,
/// ));
/// registry.registerDestination(NavigationDestination(
///   name: 'home',
///   route: '/dashboard',
///   displayLabel: 'Home',
/// ));
/// ```
class VoiceIntentRegistry {
  static final VoiceIntentRegistry _instance = VoiceIntentRegistry._internal();
  factory VoiceIntentRegistry() => _instance;
  VoiceIntentRegistry._internal();

  final Map<String, IntentDefinition> _intents = {};
  final Map<String, NavigationDestination> _destinations = {};

  /// Register an intent definition (verb).
  void registerIntent(IntentDefinition intent) {
    _intents[intent.intentName] = intent;
  }

  /// Register multiple intent definitions at once.
  void registerIntents(List<IntentDefinition> intents) {
    for (final intent in intents) {
      _intents[intent.intentName] = intent;
    }
  }

  /// Register a navigation destination (entity for the "navigate" intent).
  void registerDestination(NavigationDestination destination) {
    _destinations[destination.name.toLowerCase()] = destination;
  }

  /// Register multiple navigation destinations at once.
  void registerDestinations(List<NavigationDestination> destinations) {
    for (final dest in destinations) {
      _destinations[dest.name.toLowerCase()] = dest;
    }
  }

  /// Resolve an intent by name. Returns null if not registered.
  IntentDefinition? resolveIntent(String intentName) {
    return _intents[intentName];
  }

  /// Resolve a navigation destination by entity value.
  /// Tries exact match first, then checks aliases.
  NavigationDestination? resolveDestination(String entityValue) {
    final key = entityValue.toLowerCase().trim();
    return _destinations[key];
  }

  /// Resolve a navigation destination by its route path.
  NavigationDestination? resolveDestinationByRoute(String route) {
    for (final dest in _destinations.values) {
      if (dest.route == route) return dest;
    }
    return null;
  }

  /// All registered intent definitions.
  List<IntentDefinition> get allIntents =>
      List.unmodifiable(_intents.values);

  /// All registered navigation destinations.
  List<NavigationDestination> get allDestinations =>
      List.unmodifiable(_destinations.values);

  /// Whether any intents are registered.
  bool get isEmpty => _intents.isEmpty && _destinations.isEmpty;

  /// Total registered intents.
  int get intentCount => _intents.length;

  /// Total registered destinations.
  int get destinationCount => _destinations.length;

  /// Clear all registrations. Exposed for test isolation.
  @visibleForTesting
  void clear() {
    _intents.clear();
    _destinations.clear();
  }
}

/// Registers all default intents and destinations for the app.
/// Call once at app startup or lazily on first voice page open.
void registerDefaultVoiceIntents() {
  final registry = VoiceIntentRegistry();
  if (!registry.isEmpty) return;

  registry.registerIntents(_defaultIntents);
  registry.registerDestinations(_defaultDestinations);
}

// --- Intent definitions (verbs) ---

const _defaultIntents = [
  IntentDefinition(
    intentName: 'navigate',
    displayLabel: 'Navigate',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    entityKey: 'destination',
  ),
  IntentDefinition(
    intentName: 'call',
    displayLabel: 'Call Contact',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
    entityKey: 'contact',
  ),
  IntentDefinition(
    intentName: 'schedule',
    displayLabel: 'Schedule Appointment',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
    entityKey: 'person',
  ),
  IntentDefinition(
    intentName: 'sos',
    displayLabel: 'SOS Emergency Alert',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
  ),
  IntentDefinition(
    intentName: 'start_video_call',
    displayLabel: 'Start Video Call',
    riskLevel: IntentRiskLevel.high,
    requiresConfirmation: true,
    entityKey: 'contact',
  ),
  IntentDefinition(
    intentName: 'log_symptom',
    displayLabel: 'Log Symptom',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
    entityKey: 'symptom',
  ),
  IntentDefinition(
    intentName: 'log_medication',
    displayLabel: 'Log Medication',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
    entityKey: 'medication',
  ),
  IntentDefinition(
    intentName: 'send_message',
    displayLabel: 'Send Message',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
    entityKey: 'recipient',
  ),
  IntentDefinition(
    intentName: 'check_in',
    displayLabel: 'Start Check-In',
    riskLevel: IntentRiskLevel.medium,
    requiresConfirmation: true,
  ),
];

// --- Navigation destinations (entities for "navigate" intent) ---

const _defaultDestinations = [
  // Core
  NavigationDestination(name: 'home', route: '/dashboard', displayLabel: 'Home'),
  NavigationDestination(name: 'dashboard', route: '/dashboard', displayLabel: 'Dashboard'),
  NavigationDestination(name: 'calendar', route: '/calendar', displayLabel: 'Calendar'),
  NavigationDestination(name: 'messages', route: '/dashboard?tab=messages', displayLabel: 'Messages'),
  NavigationDestination(name: 'profile', route: '/profile', displayLabel: 'Profile'),
  NavigationDestination(name: 'settings', route: '/settings', displayLabel: 'Settings'),
  NavigationDestination(name: 'menu', route: '/dashboard?tab=menu', displayLabel: 'Menu'),

  // Health & Wellness
  NavigationDestination(name: 'symptoms', route: '/symptoms', displayLabel: 'Symptom Tracker'),
  NavigationDestination(name: 'symptom tracker', route: '/symptoms', displayLabel: 'Symptom Tracker'),
  NavigationDestination(name: 'medication', route: '/medication', displayLabel: 'Medication Tracker'),
  NavigationDestination(name: 'medications', route: '/medication', displayLabel: 'Medication Tracker'),
  NavigationDestination(name: 'medication tracker', route: '/medication', displayLabel: 'Medication Tracker'),
  NavigationDestination(name: 'virtual check-in', route: '/virtual-checkin', displayLabel: 'Virtual Check-In'),
  NavigationDestination(name: 'virtual checkin', route: '/virtual-checkin', displayLabel: 'Virtual Check-In'),
  NavigationDestination(name: 'check-in', route: '/virtual-checkin', displayLabel: 'Virtual Check-In'),

  // Integrations & Devices
  NavigationDestination(name: 'wearables', route: '/wearables', displayLabel: 'Wearables'),
  NavigationDestination(name: 'smart devices', route: '/smart-devices', displayLabel: 'Smart Devices'),
  NavigationDestination(name: 'home monitoring', route: '/home-monitoring', displayLabel: 'Home Monitoring'),

  // Social
  NavigationDestination(name: 'social feed', route: '/social-feed', displayLabel: 'Social Feed'),
  NavigationDestination(name: 'social', route: '/social-feed', displayLabel: 'Social Feed'),

  // Caregiver
  NavigationDestination(name: 'patient list', route: '/tasks', displayLabel: 'Patient List'),
  NavigationDestination(name: 'patients', route: '/tasks', displayLabel: 'Patient List'),
  NavigationDestination(name: 'evv', route: '/evv', displayLabel: 'EVV Dashboard'),
  NavigationDestination(name: 'evv dashboard', route: '/evv', displayLabel: 'EVV Dashboard'),
  NavigationDestination(name: 'notetaker', route: '/notetaker-search', displayLabel: 'Medical Notetaker'),
  NavigationDestination(name: 'medical notetaker', route: '/notetaker-search', displayLabel: 'Medical Notetaker'),
  NavigationDestination(name: 'invoice', route: '/invoice-assistant', displayLabel: 'Invoice Assistant'),
  NavigationDestination(name: 'invoice assistant', route: '/invoice-assistant', displayLabel: 'Invoice Assistant'),

  // Files & Documents
  NavigationDestination(name: 'files', route: '/file-management', displayLabel: 'File Management'),
  NavigationDestination(name: 'file management', route: '/file-management', displayLabel: 'File Management'),
  NavigationDestination(name: 'informed delivery', route: '/informed-delivery', displayLabel: 'Informed Delivery'),
  NavigationDestination(name: 'mail', route: '/informed-delivery', displayLabel: 'Informed Delivery'),

  // Gamification
  NavigationDestination(name: 'gamification', route: '/gamification', displayLabel: 'Gamification'),
  NavigationDestination(name: 'achievements', route: '/gamification', displayLabel: 'Gamification'),

  // Configuration
  NavigationDestination(name: 'ai configuration', route: '/ai-configuration', displayLabel: 'AI Configuration'),
  NavigationDestination(name: 'ai config', route: '/ai-configuration', displayLabel: 'AI Configuration'),
  NavigationDestination(name: 'notetaker configuration', route: '/notetaker-configuration', displayLabel: 'Notetaker Configuration'),

  // Payments
  NavigationDestination(name: 'subscription', route: '/subscription', displayLabel: 'Subscription'),

  // Search
  NavigationDestination(name: 'search', route: '/search', displayLabel: 'Search'),

  // Voice
  NavigationDestination(name: 'voice', route: '/voice', displayLabel: 'Voice Commands'),
  NavigationDestination(name: 'voice commands', route: '/voice', displayLabel: 'Voice Commands'),
];
