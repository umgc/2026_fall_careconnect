import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/voice_intent_registry.dart';

void main() {
  setUp(() {
    VoiceIntentRegistry().clear();
  });

  group('VoiceIntentRegistry singleton', () {
    test('factory returns same instance', () {
      final a = VoiceIntentRegistry();
      final b = VoiceIntentRegistry();
      expect(identical(a, b), isTrue);
    });

    test('starts empty after clear', () {
      expect(VoiceIntentRegistry().isEmpty, isTrue);
      expect(VoiceIntentRegistry().length, 0);
      expect(VoiceIntentRegistry().allIntents, isEmpty);
    });
  });

  group('VoiceIntentRegistry register and lookup', () {
    test('register adds intent and lookup retrieves it', () {
      const intent = IntentRegistration(
        intentName: 'test_nav',
        displayLabel: 'Test',
        routeDestination: '/test',
      );
      VoiceIntentRegistry().register(intent);

      final result = VoiceIntentRegistry().lookup('test_nav');
      expect(result, isNotNull);
      expect(result!.intentName, 'test_nav');
      expect(result.displayLabel, 'Test');
      expect(result.routeDestination, '/test');
    });

    test('lookup returns null for unknown intent', () {
      expect(VoiceIntentRegistry().lookup('nonexistent'), isNull);
    });

    test('register overwrites existing intent with same name', () {
      const first = IntentRegistration(
        intentName: 'dup',
        displayLabel: 'First',
      );
      const second = IntentRegistration(
        intentName: 'dup',
        displayLabel: 'Second',
      );
      VoiceIntentRegistry().register(first);
      VoiceIntentRegistry().register(second);

      expect(VoiceIntentRegistry().lookup('dup')!.displayLabel, 'Second');
      expect(VoiceIntentRegistry().length, 1);
    });

    test('registerAll registers multiple intents', () {
      const intents = [
        IntentRegistration(intentName: 'a', displayLabel: 'A'),
        IntentRegistration(intentName: 'b', displayLabel: 'B'),
        IntentRegistration(intentName: 'c', displayLabel: 'C'),
      ];
      VoiceIntentRegistry().registerAll(intents);

      expect(VoiceIntentRegistry().length, 3);
      expect(VoiceIntentRegistry().lookup('a'), isNotNull);
      expect(VoiceIntentRegistry().lookup('b'), isNotNull);
      expect(VoiceIntentRegistry().lookup('c'), isNotNull);
    });

    test('lookupByRoute finds intent by route destination', () {
      const intent = IntentRegistration(
        intentName: 'nav_dash',
        displayLabel: 'Dashboard',
        routeDestination: '/dashboard',
      );
      VoiceIntentRegistry().register(intent);

      final result = VoiceIntentRegistry().lookupByRoute('/dashboard');
      expect(result, isNotNull);
      expect(result!.intentName, 'nav_dash');
    });

    test('lookupByRoute returns null when no match', () {
      expect(VoiceIntentRegistry().lookupByRoute('/unknown'), isNull);
    });

    test('allIntents returns unmodifiable list of registered intents', () {
      const intents = [
        IntentRegistration(intentName: 'x', displayLabel: 'X'),
        IntentRegistration(intentName: 'y', displayLabel: 'Y'),
      ];
      VoiceIntentRegistry().registerAll(intents);

      final all = VoiceIntentRegistry().allIntents;
      expect(all.length, 2);
      expect(() => (all as List).add(const IntentRegistration(intentName: 'z', displayLabel: 'Z')), throwsA(isA<UnsupportedError>()));
    });
  });

  group('VoiceIntentRegistry defaults', () {
    test('registerDefaultVoiceIntents populates registry', () {
      registerDefaultVoiceIntents();

      expect(VoiceIntentRegistry().isEmpty, isFalse);
      expect(VoiceIntentRegistry().lookup('navigate_home'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_calendar'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_symptoms'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate'), isNotNull);
      expect(VoiceIntentRegistry().lookup('call'), isNotNull);
      expect(VoiceIntentRegistry().lookup('schedule'), isNotNull);
    });

    test('default registry covers all major app features', () {
      registerDefaultVoiceIntents();

      // Core navigation
      expect(VoiceIntentRegistry().lookup('navigate_dashboard'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_messages'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_profile'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_settings'), isNotNull);

      // Health
      expect(VoiceIntentRegistry().lookup('navigate_medication'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_virtual_checkin'), isNotNull);

      // Integrations
      expect(VoiceIntentRegistry().lookup('navigate_wearables'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_smart_devices'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_home_monitoring'), isNotNull);

      // Caregiver
      expect(VoiceIntentRegistry().lookup('navigate_patient_list'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_evv'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_notetaker'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_invoice'), isNotNull);

      // Files & docs
      expect(VoiceIntentRegistry().lookup('navigate_files'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_informed_delivery'), isNotNull);

      // Other features
      expect(VoiceIntentRegistry().lookup('navigate_gamification'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_social_feed'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_search'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_voice'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_subscription'), isNotNull);
      expect(VoiceIntentRegistry().lookup('navigate_ai_config'), isNotNull);

      // Action intents
      expect(VoiceIntentRegistry().lookup('sos'), isNotNull);
      expect(VoiceIntentRegistry().lookup('start_video_call'), isNotNull);
      expect(VoiceIntentRegistry().lookup('log_symptom'), isNotNull);
      expect(VoiceIntentRegistry().lookup('log_medication'), isNotNull);
      expect(VoiceIntentRegistry().lookup('send_message'), isNotNull);
      expect(VoiceIntentRegistry().lookup('check_in'), isNotNull);
    });

    test('default navigate intents have correct routes', () {
      registerDefaultVoiceIntents();

      expect(
        VoiceIntentRegistry().lookup('navigate_home')!.routeDestination,
        '/dashboard',
      );
      expect(
        VoiceIntentRegistry().lookup('navigate_calendar')!.routeDestination,
        '/calendar',
      );
      expect(
        VoiceIntentRegistry().lookup('navigate_symptoms')!.routeDestination,
        '/symptoms',
      );
      expect(
        VoiceIntentRegistry().lookup('navigate_messages')!.routeDestination,
        '/dashboard?tab=messages',
      );
      expect(
        VoiceIntentRegistry().lookup('navigate_medication')!.routeDestination,
        '/medication',
      );
      expect(
        VoiceIntentRegistry().lookup('navigate_evv')!.routeDestination,
        '/evv',
      );
    });

    test('default navigate intents are low risk with confirmation', () {
      registerDefaultVoiceIntents();

      final home = VoiceIntentRegistry().lookup('navigate_home')!;
      expect(home.riskLevel, IntentRiskLevel.low);
      expect(home.requiresConfirmation, isTrue);
    });

    test('action intents are high or medium risk with confirmation', () {
      registerDefaultVoiceIntents();

      final call = VoiceIntentRegistry().lookup('call')!;
      expect(call.riskLevel, IntentRiskLevel.high);
      expect(call.requiresConfirmation, isTrue);

      final schedule = VoiceIntentRegistry().lookup('schedule')!;
      expect(schedule.riskLevel, IntentRiskLevel.high);
      expect(schedule.requiresConfirmation, isTrue);

      final sos = VoiceIntentRegistry().lookup('sos')!;
      expect(sos.riskLevel, IntentRiskLevel.high);
      expect(sos.requiresConfirmation, isTrue);

      final logSymptom = VoiceIntentRegistry().lookup('log_symptom')!;
      expect(logSymptom.riskLevel, IntentRiskLevel.medium);
      expect(logSymptom.requiresConfirmation, isTrue);
    });

    test('registerDefaultVoiceIntents is idempotent', () {
      registerDefaultVoiceIntents();
      final countFirst = VoiceIntentRegistry().length;
      registerDefaultVoiceIntents();
      expect(VoiceIntentRegistry().length, countFirst);
    });
  });

  group('IntentRegistration properties', () {
    test('defaults are sensible', () {
      const intent = IntentRegistration(
        intentName: 'test',
        displayLabel: 'Test',
      );
      expect(intent.riskLevel, IntentRiskLevel.low);
      expect(intent.requiresConfirmation, isFalse);
      expect(intent.routeDestination, isNull);
      expect(intent.handler, isNull);
    });

    test('handler can be provided for action intents', () {
      var called = false;
      final intent = IntentRegistration(
        intentName: 'action',
        displayLabel: 'Action',
        handler: (entities) async { called = true; },
      );
      intent.handler!({});
      expect(called, isTrue);
    });
  });
}
