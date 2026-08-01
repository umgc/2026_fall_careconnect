import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/stml_service.dart';

void main() {
  group('StmlCard.fromJson', () {
    test('parses a fully populated card', () {
      final card = StmlCard.fromJson({
        'type': 'APPOINTMENT',
        'headline': 'Cardiology follow-up',
        'detail': 'Dr. Lee, 2pm Thursday',
        'sourceType': 'CALL_SUMMARY',
        'timestamp': '2026-07-16T14:00:00Z',
      });

      expect(card.type, 'APPOINTMENT');
      expect(card.headline, 'Cardiology follow-up');
      expect(card.detail, 'Dr. Lee, 2pm Thursday');
      expect(card.sourceType, 'CALL_SUMMARY');
      expect(card.timestamp, DateTime.parse('2026-07-16T14:00:00Z'));
    });

    test('defaults missing fields to empty string and null timestamp', () {
      final card = StmlCard.fromJson(const {});

      expect(card.type, '');
      expect(card.headline, '');
      expect(card.detail, '');
      expect(card.sourceType, '');
      expect(card.timestamp, isNull);
    });

    test('treats an unparsable timestamp as null instead of throwing', () {
      final card = StmlCard.fromJson(const {
        'type': 'ACTION_ITEM',
        'timestamp': 'not-a-date',
      });

      expect(card.timestamp, isNull);
    });
  });

  group('StmlBrief.fromJson', () {
    test('parses cards list and disclaimer', () {
      final brief = StmlBrief.fromJson({
        'patientId': 42,
        'generatedAt': '2026-07-18T07:05:00Z',
        'disclaimer': 'Based on your records.',
        'cards': [
          {'type': 'RECALL', 'headline': 'Called about medication'},
          {'type': 'MEDICATION', 'headline': 'Metformin 500mg'},
        ],
      });

      expect(brief.patientId, 42);
      expect(brief.generatedAt, DateTime.parse('2026-07-18T07:05:00Z'));
      expect(brief.disclaimer, 'Based on your records.');
      expect(brief.cards, hasLength(2));
      expect(brief.cards[0].type, 'RECALL');
      expect(brief.cards[1].type, 'MEDICATION');
    });

    test('defaults to an empty card list when cards is missing', () {
      final brief = StmlBrief.fromJson(const {'patientId': 7});

      expect(brief.cards, isEmpty);
      expect(brief.disclaimer, '');
      expect(brief.generatedAt, isNull);
    });

    test('defaults patientId to 0 when missing or non-numeric', () {
      final brief = StmlBrief.fromJson(const {});
      expect(brief.patientId, 0);
    });
  });

  group('StmlRecallResult.fromJson', () {
    test('parses answer, sources, and disclaimer', () {
      final result = StmlRecallResult.fromJson({
        'answer': 'You discussed your new blood pressure medication.',
        'disclaimer': 'Based on your records.',
        'sources': [
          {
            'sourceType': 'CALL_SUMMARY',
            'summary': 'Started lisinopril 10mg',
            'date': '2026-07-15',
          },
        ],
      });

      expect(result.answer, contains('blood pressure'));
      expect(result.disclaimer, 'Based on your records.');
      expect(result.sources, hasLength(1));
      expect(result.sources.first.sourceType, 'CALL_SUMMARY');
      expect(result.sources.first.date, '2026-07-15');
    });

    test('defaults to empty sources when missing', () {
      final result = StmlRecallResult.fromJson(const {'answer': 'No records.'});
      expect(result.sources, isEmpty);
    });
  });

  group('StmlCheckIn.fromJson', () {
    test('parses consentGranted true with notes and pending items', () {
      final checkIn = StmlCheckIn.fromJson({
        'consentGranted': true,
        'disclaimer': 'Based on your records.',
        'notes': [
          {
            'type': 'NOTE',
            'summary': 'Patient reported mild pain',
            'date': '2026-07-17',
            'source': 'CALL_SUMMARY',
          },
        ],
        'pendingItems': [
          {'type': 'ACTION_ITEM', 'summary': 'Schedule follow-up'},
        ],
      });

      expect(checkIn.consentGranted, isTrue);
      expect(checkIn.notes, hasLength(1));
      expect(checkIn.notes.first.summary, 'Patient reported mild pain');
      expect(checkIn.pendingItems, hasLength(1));
    });

    test('defaults consentGranted to false when missing', () {
      final checkIn = StmlCheckIn.fromJson(const {});
      expect(checkIn.consentGranted, isFalse);
      expect(checkIn.notes, isEmpty);
      expect(checkIn.pendingItems, isEmpty);
    });
  });

  group('StmlSearchResults.fromJson', () {
    test('parses totalResults and results list', () {
      final results = StmlSearchResults.fromJson({
        'totalResults': 2,
        'results': [
          {
            'sourceType': 'USPS_MAIL',
            'content': 'Insurance statement',
            'sender': 'Aetna',
            'date': '2026-07-10',
            'conversationId': 'conv-1',
          },
          {
            'sourceType': 'CALL_SUMMARY',
            'content': 'Discussed medication refill',
            'sender': 'Caregiver',
            'date': '2026-07-12',
            'conversationId': 'conv-2',
          },
        ],
      });

      expect(results.totalResults, 2);
      expect(results.results, hasLength(2));
      expect(results.results[0].sourceType, 'USPS_MAIL');
      expect(results.results[1].conversationId, 'conv-2');
    });

    test('defaults to zero results and empty list when missing', () {
      final results = StmlSearchResults.fromJson(const {});
      expect(results.totalResults, 0);
      expect(results.results, isEmpty);
    });
  });

  group('StmlException', () {
    test('toString returns the message unmodified', () {
      final exception = StmlException("You aren't authorized.");
      expect(exception.toString(), "You aren't authorized.");
    });
  });
}
