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
      expect(VoiceIntentRegistry().intentCount, 0);
      expect(VoiceIntentRegistry().destinationCount, 0);
      expect(VoiceIntentRegistry().allIntents, isEmpty);
      expect(VoiceIntentRegistry().allDestinations, isEmpty);
    });
  });

  group('VoiceIntentRegistry intent registration', () {
    test('registerIntent adds intent and resolveIntent retrieves it', () {
      const intent = IntentDefinition(
        intentName: 'navigate',
        displayLabel: 'Navigate',
        entityKey: 'destination',
      );
      VoiceIntentRegistry().registerIntent(intent);

      final result = VoiceIntentRegistry().resolveIntent('navigate');
      expect(result, isNotNull);
      expect(result!.intentName, 'navigate');
      expect(result.displayLabel, 'Navigate');
      expect(result.entityKey, 'destination');
    });

    test('resolveIntent returns null for unknown intent', () {
      expect(VoiceIntentRegistry().resolveIntent('nonexistent'), isNull);
    });

    test('registerIntent overwrites existing intent with same name', () {
      const first = IntentDefinition(
        intentName: 'dup',
        displayLabel: 'First',
      );
      const second = IntentDefinition(
        intentName: 'dup',
        displayLabel: 'Second',
      );
      VoiceIntentRegistry().registerIntent(first);
      VoiceIntentRegistry().registerIntent(second);

      expect(VoiceIntentRegistry().resolveIntent('dup')!.displayLabel, 'Second');
      expect(VoiceIntentRegistry().intentCount, 1);
    });

    test('registerIntents registers multiple intents', () {
      const intents = [
        IntentDefinition(intentName: 'a', displayLabel: 'A'),
        IntentDefinition(intentName: 'b', displayLabel: 'B'),
        IntentDefinition(intentName: 'c', displayLabel: 'C'),
      ];
      VoiceIntentRegistry().registerIntents(intents);

      expect(VoiceIntentRegistry().intentCount, 3);
      expect(VoiceIntentRegistry().resolveIntent('a'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('b'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('c'), isNotNull);
    });

    test('allIntents returns unmodifiable list', () {
      const intents = [
        IntentDefinition(intentName: 'x', displayLabel: 'X'),
        IntentDefinition(intentName: 'y', displayLabel: 'Y'),
      ];
      VoiceIntentRegistry().registerIntents(intents);

      final all = VoiceIntentRegistry().allIntents;
      expect(all.length, 2);
      expect(
        () => (all as List).add(const IntentDefinition(intentName: 'z', displayLabel: 'Z')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('VoiceIntentRegistry destination registration', () {
    test('registerDestination adds and resolveDestination retrieves', () {
      const dest = NavigationDestination(
        name: 'home',
        route: '/dashboard',
        displayLabel: 'Home',
      );
      VoiceIntentRegistry().registerDestination(dest);

      final result = VoiceIntentRegistry().resolveDestination('home');
      expect(result, isNotNull);
      expect(result!.name, 'home');
      expect(result.route, '/dashboard');
      expect(result.displayLabel, 'Home');
    });

    test('resolveDestination is case-insensitive', () {
      const dest = NavigationDestination(
        name: 'Calendar',
        route: '/calendar',
        displayLabel: 'Calendar',
      );
      VoiceIntentRegistry().registerDestination(dest);

      expect(VoiceIntentRegistry().resolveDestination('calendar'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('CALENDAR'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('Calendar'), isNotNull);
    });

    test('resolveDestination returns null for unknown destination', () {
      expect(VoiceIntentRegistry().resolveDestination('nowhere'), isNull);
    });

    test('resolveDestinationByRoute finds destination by route', () {
      const dest = NavigationDestination(
        name: 'calendar',
        route: '/calendar',
        displayLabel: 'Calendar',
      );
      VoiceIntentRegistry().registerDestination(dest);

      final result = VoiceIntentRegistry().resolveDestinationByRoute('/calendar');
      expect(result, isNotNull);
      expect(result!.name, 'calendar');
    });

    test('resolveDestinationByRoute returns null for unknown route', () {
      expect(VoiceIntentRegistry().resolveDestinationByRoute('/unknown'), isNull);
    });

    test('registerDestinations registers multiple destinations', () {
      const destinations = [
        NavigationDestination(name: 'home', route: '/dashboard', displayLabel: 'Home'),
        NavigationDestination(name: 'calendar', route: '/calendar', displayLabel: 'Calendar'),
        NavigationDestination(name: 'settings', route: '/settings', displayLabel: 'Settings'),
      ];
      VoiceIntentRegistry().registerDestinations(destinations);

      expect(VoiceIntentRegistry().destinationCount, 3);
      expect(VoiceIntentRegistry().resolveDestination('home'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('calendar'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('settings'), isNotNull);
    });

    test('allDestinations returns unmodifiable list', () {
      const destinations = [
        NavigationDestination(name: 'a', route: '/a', displayLabel: 'A'),
        NavigationDestination(name: 'b', route: '/b', displayLabel: 'B'),
      ];
      VoiceIntentRegistry().registerDestinations(destinations);

      final all = VoiceIntentRegistry().allDestinations;
      expect(all.length, 2);
      expect(
        () => (all as List).add(const NavigationDestination(name: 'z', route: '/z', displayLabel: 'Z')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('VoiceIntentRegistry defaults', () {
    test('registerDefaultVoiceIntents populates registry', () {
      registerDefaultVoiceIntents();

      expect(VoiceIntentRegistry().isEmpty, isFalse);
      expect(VoiceIntentRegistry().resolveIntent('navigate'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('call'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('schedule'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('sos'), isNotNull);
    });

    test('default intents cover all action verbs', () {
      registerDefaultVoiceIntents();

      expect(VoiceIntentRegistry().resolveIntent('navigate'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('call'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('schedule'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('sos'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('start_video_call'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('log_symptom'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('log_medication'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('send_message'), isNotNull);
      expect(VoiceIntentRegistry().resolveIntent('check_in'), isNotNull);
    });

    test('default destinations cover all app features', () {
      registerDefaultVoiceIntents();

      // Core navigation
      expect(VoiceIntentRegistry().resolveDestination('home'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('dashboard'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('calendar'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('messages'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('profile'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('settings'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('menu'), isNotNull);

      // Health
      expect(VoiceIntentRegistry().resolveDestination('symptoms'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('medication'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('virtual checkin'), isNotNull);

      // Integrations
      expect(VoiceIntentRegistry().resolveDestination('wearables'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('smart devices'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('home monitoring'), isNotNull);

      // Social
      expect(VoiceIntentRegistry().resolveDestination('social feed'), isNotNull);

      // Caregiver
      expect(VoiceIntentRegistry().resolveDestination('patient list'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('evv'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('notetaker'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('invoice'), isNotNull);

      // Files
      expect(VoiceIntentRegistry().resolveDestination('files'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('informed delivery'), isNotNull);

      // Other
      expect(VoiceIntentRegistry().resolveDestination('gamification'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('search'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('subscription'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('voice'), isNotNull);
      expect(VoiceIntentRegistry().resolveDestination('ai configuration'), isNotNull);
    });

    test('default destinations have correct routes', () {
      registerDefaultVoiceIntents();

      expect(
        VoiceIntentRegistry().resolveDestination('home')!.route,
        '/dashboard',
      );
      expect(
        VoiceIntentRegistry().resolveDestination('calendar')!.route,
        '/calendar',
      );
      expect(
        VoiceIntentRegistry().resolveDestination('symptoms')!.route,
        '/symptoms',
      );
      expect(
        VoiceIntentRegistry().resolveDestination('messages')!.route,
        '/dashboard?tab=messages',
      );
      expect(
        VoiceIntentRegistry().resolveDestination('medication')!.route,
        '/medication',
      );
      expect(
        VoiceIntentRegistry().resolveDestination('evv')!.route,
        '/evv',
      );
    });

    test('navigate intent is low risk with confirmation', () {
      registerDefaultVoiceIntents();

      final nav = VoiceIntentRegistry().resolveIntent('navigate')!;
      expect(nav.riskLevel, IntentRiskLevel.low);
      expect(nav.requiresConfirmation, isTrue);
      expect(nav.entityKey, 'destination');
    });

    test('action intents are high or medium risk with confirmation', () {
      registerDefaultVoiceIntents();

      final call = VoiceIntentRegistry().resolveIntent('call')!;
      expect(call.riskLevel, IntentRiskLevel.high);
      expect(call.requiresConfirmation, isTrue);

      final schedule = VoiceIntentRegistry().resolveIntent('schedule')!;
      expect(schedule.riskLevel, IntentRiskLevel.high);
      expect(schedule.requiresConfirmation, isTrue);

      final sos = VoiceIntentRegistry().resolveIntent('sos')!;
      expect(sos.riskLevel, IntentRiskLevel.high);
      expect(sos.requiresConfirmation, isTrue);

      final logSymptom = VoiceIntentRegistry().resolveIntent('log_symptom')!;
      expect(logSymptom.riskLevel, IntentRiskLevel.medium);
      expect(logSymptom.requiresConfirmation, isTrue);
    });

    test('registerDefaultVoiceIntents is idempotent', () {
      registerDefaultVoiceIntents();
      final intentCount = VoiceIntentRegistry().intentCount;
      final destCount = VoiceIntentRegistry().destinationCount;
      registerDefaultVoiceIntents();
      expect(VoiceIntentRegistry().intentCount, intentCount);
      expect(VoiceIntentRegistry().destinationCount, destCount);
    });

    test('destination aliases resolve to same route', () {
      registerDefaultVoiceIntents();

      final patients = VoiceIntentRegistry().resolveDestination('patients');
      final patientList = VoiceIntentRegistry().resolveDestination('patient list');
      expect(patients, isNotNull);
      expect(patientList, isNotNull);
      expect(patients!.route, patientList!.route);
    });
  });

  group('IntentDefinition properties', () {
    test('defaults are sensible', () {
      const intent = IntentDefinition(
        intentName: 'test',
        displayLabel: 'Test',
      );
      expect(intent.riskLevel, IntentRiskLevel.low);
      expect(intent.requiresConfirmation, isFalse);
      expect(intent.entityKey, isNull);
      expect(intent.handler, isNull);
    });

    test('handler can be provided for action intents', () {
      var called = false;
      final intent = IntentDefinition(
        intentName: 'action',
        displayLabel: 'Action',
        handler: (entities) async { called = true; },
      );
      intent.handler!({});
      expect(called, isTrue);
    });
  });
}
