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
  IntentRegistration(
    intentName: 'navigate_home',
    displayLabel: 'Home',
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
    intentName: 'navigate_symptoms',
    displayLabel: 'Symptom Tracker',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
    routeDestination: '/symptoms',
  ),
  IntentRegistration(
    intentName: 'navigate',
    displayLabel: 'Navigate',
    riskLevel: IntentRiskLevel.low,
    requiresConfirmation: true,
  ),
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
];
