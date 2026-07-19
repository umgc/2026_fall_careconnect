import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/services/daily_brief_gate_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const patientId = 42;
  const otherPatientId = 99;
  final morning = DateTime(2026, 7, 18, 8, 0);
  final beforeSeven = DateTime(2026, 7, 18, 6, 59);
  final nextDayMorning = DateTime(2026, 7, 19, 7, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DailyBriefGateService.shouldShow', () {
    test('returns false before 7am local time', () async {
      final result =
          await DailyBriefGateService.shouldShow(patientId, now: beforeSeven);
      expect(result, isFalse);
    });

    test('returns true at/after 7am when not yet marked seen today', () async {
      final result =
          await DailyBriefGateService.shouldShow(patientId, now: morning);
      expect(result, isTrue);
    });

    test('does not mark seen as a side effect', () async {
      await DailyBriefGateService.shouldShow(patientId, now: morning);
      final stillShows =
          await DailyBriefGateService.shouldShow(patientId, now: morning);
      expect(stillShows, isTrue);
    });

    test('returns false same day after markSeen', () async {
      await DailyBriefGateService.markSeen(patientId, now: morning);
      final result =
          await DailyBriefGateService.shouldShow(patientId, now: morning);
      expect(result, isFalse);
    });

    test('returns true again once the calendar date rolls over', () async {
      await DailyBriefGateService.markSeen(patientId, now: morning);
      final result = await DailyBriefGateService.shouldShow(
        patientId,
        now: nextDayMorning,
      );
      expect(result, isTrue);
    });

    test('is scoped per patientId — marking one patient seen does not '
        'affect another', () async {
      await DailyBriefGateService.markSeen(patientId, now: morning);
      final otherStillShows = await DailyBriefGateService.shouldShow(
        otherPatientId,
        now: morning,
      );
      expect(otherStillShows, isTrue);
    });
  });

  group('DailyBriefGateService.resetForTesting', () {
    test('clears the marker so shouldShow becomes true again', () async {
      await DailyBriefGateService.markSeen(patientId, now: morning);
      await DailyBriefGateService.resetForTesting(patientId);
      final result =
          await DailyBriefGateService.shouldShow(patientId, now: morning);
      expect(result, isTrue);
    });
  });
}
