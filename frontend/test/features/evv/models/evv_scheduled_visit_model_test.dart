// Tests for the EVV ScheduledVisit model defined at the bottom of schedule_page.dart.
// Covers: constructor, fromJson (date/time parsing, duration, priority default).

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';

void main() {
  group('EVV ScheduledVisit constructor', () {
    test('stores all required fields', () {
      // Arrange + Act
      final visit = ScheduledVisit(
        id: 1,
        patientId: 10,
        patientName: 'John Doe',
        serviceType: 'Personal Care',
        scheduledTime: DateTime(2026, 3, 17, 10, 0),
        duration: const Duration(minutes: 60),
        status: 'Scheduled',
        priority: 'Normal',
      );

      // Assert
      expect(visit.id, 1);
      expect(visit.patientId, 10);
      expect(visit.patientName, 'John Doe');
      expect(visit.serviceType, 'Personal Care');
      expect(visit.scheduledTime, DateTime(2026, 3, 17, 10, 0));
      expect(visit.duration, const Duration(minutes: 60));
      expect(visit.status, 'Scheduled');
      expect(visit.priority, 'Normal');
    });
  });

  group('EVV ScheduledVisit.fromJson', () {
    test('parses all fields from valid JSON', () {
      // Arrange
      final json = {
        'id': 42,
        'patientId': 10,
        'patientName': 'Alice Smith',
        'serviceType': 'Skilled Nursing',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:30:00',
        'durationMinutes': 90,
        'status': 'Scheduled',
        'priority': 'High',
      };

      // Act
      final visit = ScheduledVisit.fromJson(json);

      // Assert
      expect(visit.id, 42);
      expect(visit.patientId, 10);
      expect(visit.patientName, 'Alice Smith');
      expect(visit.serviceType, 'Skilled Nursing');
      expect(visit.scheduledTime, DateTime(2026, 3, 17, 10, 30));
      expect(visit.duration, const Duration(minutes: 90));
      expect(visit.status, 'Scheduled');
      expect(visit.priority, 'High');
    });

    test('parses time with HH:mm format (no seconds)', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-06-15',
        'scheduledTime': '14:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime.hour, 14);
      expect(visit.scheduledTime.minute, 0);
    });

    test('parses time with HH:mm:ss format', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-06-15',
        'scheduledTime': '09:30:00',
        'durationMinutes': 45,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime.hour, 9);
      expect(visit.scheduledTime.minute, 30);
    });

    test('priority defaults to Normal when null', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
        'priority': null,
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.priority, 'Normal');
    });

    test('priority defaults to Normal when key absent', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.priority, 'Normal');
    });

    test('parses date correctly', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-12-25',
        'scheduledTime': '08:00',
        'durationMinutes': 120,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime.year, 2026);
      expect(visit.scheduledTime.month, 12);
      expect(visit.scheduledTime.day, 25);
    });

    test('duration stored as Duration object', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'durationMinutes': 30,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.duration.inMinutes, 30);
    });

    test('handles midnight time', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '00:00:00',
        'durationMinutes': 60,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime.hour, 0);
      expect(visit.scheduledTime.minute, 0);
    });

    test('handles end of day time', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '23:59',
        'durationMinutes': 15,
        'status': 'Scheduled',
      };

      final visit = ScheduledVisit.fromJson(json);
      expect(visit.scheduledTime.hour, 23);
      expect(visit.scheduledTime.minute, 59);
    });

    test('preserves all status values', () {
      for (final status in ['Scheduled', 'In Progress', 'Completed', 'Cancelled']) {
        final json = {
          'id': 1,
          'patientId': 10,
          'patientName': 'Test',
          'serviceType': 'Care',
          'scheduledDate': '2026-03-17',
          'scheduledTime': '10:00',
          'durationMinutes': 60,
          'status': status,
        };
        expect(ScheduledVisit.fromJson(json).status, status);
      }
    });

    test('minimum 15-minute duration', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '10:00',
        'durationMinutes': 15,
        'status': 'Scheduled',
      };

      expect(ScheduledVisit.fromJson(json).duration.inMinutes, 15);
    });

    test('maximum 480-minute (8 hour) duration', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'patientName': 'Test',
        'serviceType': 'Care',
        'scheduledDate': '2026-03-17',
        'scheduledTime': '08:00',
        'durationMinutes': 480,
        'status': 'Scheduled',
      };

      expect(ScheduledVisit.fromJson(json).duration.inMinutes, 480);
    });
  });
}
