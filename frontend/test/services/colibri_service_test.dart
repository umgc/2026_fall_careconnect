import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/colibri_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ColibriService - Tiered Clinical Safety Triage Tests', () {
    test('shouldEscalateToCloud returns false for routine account and scheduling queries', () {
      expect(ColibriService.shouldEscalateToCloud(''), isFalse);
      expect(ColibriService.shouldEscalateToCloud('   '), isFalse);
      expect(ColibriService.shouldEscalateToCloud('When is my next appointment?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Who is my doctor?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('What medications am I currently taking?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Show my daily check-in tasks'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Good morning, how are you today?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('How do I update my profile phone number?'), isFalse);
    });

    test('shouldEscalateToCloud returns true for dosage alteration requests', () {
      // User's exact prompt scenario: "can i cut dosage in half"
      expect(ColibriService.shouldEscalateToCloud('Can I cut my dosage in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I cut dosage in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I cut this pill in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Should I split my pill?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I double my dose because I forgot yesterday?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Should I stop taking my medication?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I skip my morning dose?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I halve my tablet dose?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('I want to break the tablet in half'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Are there side effects or drug interactions?'), isTrue);
    });

    test('shouldEscalateToCloud returns true for clinical symptoms and diagnosis', () {
      expect(ColibriService.shouldEscalateToCloud('I have severe chest pain and dizziness'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Please diagnose my symptoms of shortness of breath'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('I have an emergency allergic reaction'), isTrue);
    });

    test('shouldEscalateToCloud returns true for multi-campus external clinic inquiries', () {
      // User's exact prompt scenario: "where is my clinic other office located"
      expect(ColibriService.shouldEscalateToCloud('Where is my clinic other office located?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Where is the another office?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('What is the address of the other clinic branch?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Directions to the downtown location campus'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Where is the second facility?'), isTrue);
    });

    test('getDefaultColibriUrl returns valid HTTP URL', () {
      final colibri = ColibriService();
      final url = colibri.getDefaultColibriUrl();
      expect(url, startsWith('http://'));
      expect(url, contains(':8000/v1'));
    });

    test('queryLocalClinicalAssistant escalates immediate clinical questions', () async {
      final colibri = ColibriService();
      final result = await colibri.queryLocalClinicalAssistant(
        question: 'Can I cut my dosage in half?',
      );

      expect(result['success'], isTrue);
      expect(result['escalateToCloud'], isTrue);
      expect(result['content'], contains(ColibriService.escalateToken));
    });

    test('escalateToken constant matches cloud contract', () {
      expect(ColibriService.escalateToken, equals('[ESCALATE_TO_CLINICAL_CLOUD]'));
    });
  });
}
