// Tests for ScheduledVisit, VisitConflict, and ScheduledVisitAudit models.
// (lib/features/shift_scheduling/models/scheduled_visit_model.dart)
//
// Covers: constructor, fromJson (all fields + defaults + null handling),
// getEndTime, getPriorityColor, getStatusColor, _parseTimeOfDay edge cases,
// VisitConflict construction, and ScheduledVisitAudit.fromJson.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

void main() {
  // =========================================================================
  // ScheduledVisit.fromJson
  // =========================================================================

  group('ScheduledVisit.fromJson', () {
    test('parses all required fields from valid JSON', () {
      // Arrange
      final json = {
        'id': 42,
        'caregiverId': 1,
        'patientId': 10,
        'patientName': 'John Doe',
        'serviceType': 'Personal Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:30',
        'durationMinutes': 90,
        'priority': 'High',
        'notes': 'Bring medications',
        'status': 'Scheduled',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T09:00:00',
      };

      // Act
      final visit = ScheduledVisit.fromJson(json);

      // Assert
      expect(visit.id, 42);
      expect(visit.caregiverId, 1);
      expect(visit.patientId, 10);
      expect(visit.patientName, 'John Doe');
      expect(visit.serviceType, 'Personal Care');
      expect(visit.scheduledDate, DateTime(2026, 3, 17));
      expect(visit.scheduledTime, const TimeOfDay(hour: 10, minute: 30));
      expect(visit.durationMinutes, 90);
      expect(visit.priority, 'High');
      expect(visit.notes, 'Bring medications');
      expect(visit.status, 'Scheduled');
    });

    test('uses defaults when fields are null', () {
      // Arrange — minimal JSON with all nulls.
      final json = <String, dynamic>{};

      // Act
      final visit = ScheduledVisit.fromJson(json);

      // Assert — every field uses its default.
      expect(visit.id, 0);
      expect(visit.caregiverId, 0);
      expect(visit.patientId, 0);
      expect(visit.patientName, '');
      expect(visit.serviceType, '');
      expect(visit.durationMinutes, 60);
      expect(visit.priority, 'Normal');
      expect(visit.notes, isNull);
      expect(visit.status, 'Scheduled');
    });

    test('parses scheduledTime with seconds (HH:mm:ss)', () {
      final json = {
        'scheduledTime': '14:30:00',
        'scheduledDate': '2026-03-17',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      };
      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime, const TimeOfDay(hour: 14, minute: 30));
    });

    test('parses scheduledTime with just hours and minutes', () {
      final json = {
        'scheduledTime': '09:00',
        'scheduledDate': '2026-03-17',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      };
      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime, const TimeOfDay(hour: 9, minute: 0));
    });

    test('handles malformed time string with fallback', () {
      final json = {
        'scheduledTime': 'not-a-time',
        'scheduledDate': '2026-03-17',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      };
      final visit = ScheduledVisit.fromJson(json);
      // Falls back to TimeOfDay.now() — just verify it doesn't throw.
      expect(visit.scheduledTime, isA<TimeOfDay>());
    });

    test('handles empty time string with fallback', () {
      final json = {
        'scheduledTime': '',
        'scheduledDate': '2026-03-17',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      };
      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime, isA<TimeOfDay>());
    });

    test('notes can be null in JSON', () {
      final json = {
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
        'notes': null,
      };
      final visit = ScheduledVisit.fromJson(json);
      expect(visit.notes, isNull);
    });

    test('notes can be a non-null string in JSON', () {
      final json = {
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
        'notes': 'Check blood pressure',
      };
      final visit = ScheduledVisit.fromJson(json);
      expect(visit.notes, 'Check blood pressure');
    });
  });

  // =========================================================================
  // ScheduledVisit.getEndTime
  // =========================================================================

  group('ScheduledVisit.getEndTime', () {
    ScheduledVisit _makeVisit({
      required int hour,
      required int minute,
      required int duration,
    }) {
      return ScheduledVisit(
        id: 1,
        caregiverId: 1,
        patientId: 10,
        patientName: 'Test',
        serviceType: 'Care',
        scheduledDate: DateTime(2026, 3, 17),
        scheduledTime: TimeOfDay(hour: hour, minute: minute),
        durationMinutes: duration,
        priority: 'Normal',
        status: 'Scheduled',
        createdAt: DateTime(2026, 3, 17),
        updatedAt: DateTime(2026, 3, 17),
      );
    }

    test('60-minute visit from 10:00 ends at 11:00', () {
      expect(_makeVisit(hour: 10, minute: 0, duration: 60).getEndTime(), '11:00');
    });

    test('90-minute visit from 09:30 ends at 11:00', () {
      expect(_makeVisit(hour: 9, minute: 30, duration: 90).getEndTime(), '11:00');
    });

    test('30-minute visit from 14:45 ends at 15:15', () {
      expect(_makeVisit(hour: 14, minute: 45, duration: 30).getEndTime(), '15:15');
    });

    test('15-minute minimum visit', () {
      expect(_makeVisit(hour: 8, minute: 0, duration: 15).getEndTime(), '08:15');
    });

    test('480-minute maximum visit from 08:00 ends at 16:00', () {
      expect(_makeVisit(hour: 8, minute: 0, duration: 480).getEndTime(), '16:00');
    });

    test('visit spanning past midnight wraps hours', () {
      // 23:00 + 120 min = 25:00 → "25:00" (no date wrapping in this model)
      expect(_makeVisit(hour: 23, minute: 0, duration: 120).getEndTime(), '25:00');
    });

    test('zero-minute duration returns same time', () {
      expect(_makeVisit(hour: 10, minute: 30, duration: 0).getEndTime(), '10:30');
    });
  });

  // =========================================================================
  // ScheduledVisit.getPriorityColor
  // =========================================================================

  group('ScheduledVisit.getPriorityColor', () {
    ScheduledVisit _makeWithPriority(String priority) {
      return ScheduledVisit(
        id: 1, caregiverId: 1, patientId: 10, patientName: 'T',
        serviceType: 'C', scheduledDate: DateTime(2026, 3, 17),
        scheduledTime: const TimeOfDay(hour: 10, minute: 0),
        durationMinutes: 60, priority: priority, status: 'Scheduled',
        createdAt: DateTime(2026, 3, 17), updatedAt: DateTime(2026, 3, 17),
      );
    }

    test('High priority returns red', () {
      expect(_makeWithPriority('High').getPriorityColor(), Colors.red);
    });

    test('high (lowercase) returns red', () {
      expect(_makeWithPriority('high').getPriorityColor(), Colors.red);
    });

    test('Medium priority returns orange', () {
      expect(_makeWithPriority('Medium').getPriorityColor(), Colors.orange);
    });

    test('Low priority returns green', () {
      expect(_makeWithPriority('Low').getPriorityColor(), Colors.green);
    });

    test('Normal priority returns blue (default)', () {
      expect(_makeWithPriority('Normal').getPriorityColor(), Colors.blue);
    });

    test('unknown priority returns blue (default)', () {
      expect(_makeWithPriority('Urgent').getPriorityColor(), Colors.blue);
    });

    test('empty string returns blue (default)', () {
      expect(_makeWithPriority('').getPriorityColor(), Colors.blue);
    });
  });

  // =========================================================================
  // ScheduledVisit.getStatusColor
  // =========================================================================

  group('ScheduledVisit.getStatusColor', () {
    ScheduledVisit _makeWithStatus(String status) {
      return ScheduledVisit(
        id: 1, caregiverId: 1, patientId: 10, patientName: 'T',
        serviceType: 'C', scheduledDate: DateTime(2026, 3, 17),
        scheduledTime: const TimeOfDay(hour: 10, minute: 0),
        durationMinutes: 60, priority: 'Normal', status: status,
        createdAt: DateTime(2026, 3, 17), updatedAt: DateTime(2026, 3, 17),
      );
    }

    test('Completed returns green', () {
      expect(_makeWithStatus('Completed').getStatusColor(), Colors.green);
    });

    test('completed (lowercase) returns green', () {
      expect(_makeWithStatus('completed').getStatusColor(), Colors.green);
    });

    test('Cancelled returns grey', () {
      expect(_makeWithStatus('Cancelled').getStatusColor(), Colors.grey);
    });

    test('Scheduled returns blue', () {
      expect(_makeWithStatus('Scheduled').getStatusColor(), Colors.blue);
    });

    test('unknown status returns amber (default)', () {
      expect(_makeWithStatus('In Progress').getStatusColor(), Colors.amber);
    });

    test('empty status returns amber (default)', () {
      expect(_makeWithStatus('').getStatusColor(), Colors.amber);
    });
  });

  // =========================================================================
  // VisitConflict
  // =========================================================================

  group('VisitConflict', () {
    test('constructor stores all fields', () {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Overlapping visit detected',
      );
      expect(conflict.conflictingVisits, isEmpty);
      expect(conflict.conflictType, 'caregiver');
      expect(conflict.message, 'Overlapping visit detected');
    });

    test('can hold multiple conflicting visits', () {
      final visit1 = ScheduledVisit.fromJson({
        'id': 1,
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      });
      final visit2 = ScheduledVisit.fromJson({
        'id': 2,
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:30',
        'createdAt': '2026-03-17T08:00:00',
        'updatedAt': '2026-03-17T08:00:00',
      });

      final conflict = VisitConflict(
        conflictingVisits: [visit1, visit2],
        conflictType: 'patient',
        message: '2 overlapping visits',
      );
      expect(conflict.conflictingVisits.length, 2);
      expect(conflict.conflictType, 'patient');
    });
  });

  // =========================================================================
  // ScheduledVisitAudit.fromJson
  // =========================================================================

  group('ScheduledVisitAudit.fromJson', () {
    test('parses all fields from valid JSON', () {
      final json = {
        'id': 5,
        'visitId': 42,
        'action': 'UPDATED',
        'changedField': 'scheduledTime',
        'oldValue': '10:00',
        'newValue': '11:00',
        'changedAt': '2026-03-17T12:00:00',
        'changedBy': 'admin@careconnect.com',
      };

      final audit = ScheduledVisitAudit.fromJson(json);

      expect(audit.id, 5);
      expect(audit.visitId, 42);
      expect(audit.action, 'UPDATED');
      expect(audit.changedField, 'scheduledTime');
      expect(audit.oldValue, '10:00');
      expect(audit.newValue, '11:00');
      expect(audit.changedAt, DateTime(2026, 3, 17, 12, 0));
      expect(audit.changedBy, 'admin@careconnect.com');
    });

    test('uses defaults when fields are null', () {
      final json = <String, dynamic>{};
      final audit = ScheduledVisitAudit.fromJson(json);

      expect(audit.id, 0);
      expect(audit.visitId, 0);
      expect(audit.action, '');
      expect(audit.changedField, isNull);
      expect(audit.oldValue, isNull);
      expect(audit.newValue, isNull);
      expect(audit.changedBy, 'Unknown');
    });

    test('CREATED action has null changedField and oldValue', () {
      final json = {
        'id': 1,
        'visitId': 100,
        'action': 'CREATED',
        'changedField': null,
        'oldValue': null,
        'newValue': '{"id":100}',
        'changedAt': '2026-03-17T08:00:00',
        'changedBy': 'system',
      };
      final audit = ScheduledVisitAudit.fromJson(json);

      expect(audit.action, 'CREATED');
      expect(audit.changedField, isNull);
      expect(audit.oldValue, isNull);
      expect(audit.newValue, '{"id":100}');
    });

    test('DELETED action stores full_record', () {
      final json = {
        'id': 2,
        'visitId': 100,
        'action': 'DELETED',
        'changedField': 'full_record',
        'oldValue': '{"id":100,"status":"Cancelled"}',
        'newValue': '',
        'changedAt': '2026-03-17T14:00:00',
        'changedBy': 'admin',
      };
      final audit = ScheduledVisitAudit.fromJson(json);

      expect(audit.action, 'DELETED');
      expect(audit.changedField, 'full_record');
      expect(audit.oldValue, contains('Cancelled'));
    });
  });
}
