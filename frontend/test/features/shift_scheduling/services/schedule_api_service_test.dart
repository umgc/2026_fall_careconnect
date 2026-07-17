// Tests for ScheduleApiService.
// (lib/features/shift_scheduling/services/schedule_api_service.dart)
//
// Error-path and constructor tests only. Successful HTTP paths require
// injecting ApiClient.instance which is a separate singleton.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/services/schedule_api_service.dart';

void main() {
  group('ScheduleApiService', () {
    late ScheduleApiService service;

    setUp(() {
      service = ScheduleApiService();
    });

    test('can be instantiated', () {
      expect(service, isA<ScheduleApiService>());
    });

    test('getDaySchedule returns empty list on error', () async {
      final visits = await service.getDaySchedule(1, DateTime(2026, 3, 17));
      expect(visits, isA<List>());
    });

    test('getMonthSchedule returns empty list on error', () async {
      final visits = await service.getMonthSchedule(1, 2026, 3);
      expect(visits, isA<List>());
    });

    test('getWeekSchedule returns empty list on error', () async {
      final visits = await service.getWeekSchedule(1, DateTime(2026, 3, 16));
      expect(visits, isA<List>());
    });

    test('checkConflicts returns null on error', () async {
      final conflict = await service.checkConflicts(1, {
        'patientId': 10,
        'scheduledDate': '2026-03-17',
      });
      expect(conflict, isNull);
    });

    test('getAuditHistory returns empty list on error', () async {
      final audits = await service.getAuditHistory(42);
      expect(audits, isA<List>());
    });
  });
}
