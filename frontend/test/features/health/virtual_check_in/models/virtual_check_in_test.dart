// Tests for VirtualCheckIn, CheckInType, CheckInStatus
// (lib/features/health/virtual_check_in/models/virtual_check_in.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in.dart';

VirtualCheckIn _basic() => VirtualCheckIn(
      id: 'vc-1',
      type: CheckInType.routine,
      clinicianName: 'Dr. Smith',
      startedAt: DateTime(2025, 12, 4, 10, 30),
      durationMinutes: 15,
      status: CheckInStatus.completed,
      moodLabel: 'Good',
      nextCheckIn: DateTime(2025, 12, 11),
      summary: 'All vitals normal.',
    );

void main() {
  group('CheckInType enum', () {
    test('has routine, followUp, urgent', () {
      expect(CheckInType.values,
          containsAll([CheckInType.routine, CheckInType.followUp, CheckInType.urgent]));
    });

    test('has exactly 3 values', () {
      expect(CheckInType.values.length, 3);
    });
  });

  group('CheckInStatus enum', () {
    test('has draft, submitted, reviewed, completed, missed, cancelled', () {
      expect(
        CheckInStatus.values,
        containsAll([
          CheckInStatus.draft,
          CheckInStatus.submitted,
          CheckInStatus.reviewed,
          CheckInStatus.completed,
          CheckInStatus.missed,
          CheckInStatus.cancelled,
        ]),
      );
    });

    test('has exactly 6 values', () {
      expect(CheckInStatus.values.length, 6);
    });
  });

  group('VirtualCheckIn constructor', () {
    test('stores all required fields', () {
      final vc = _basic();
      expect(vc.id, 'vc-1');
      expect(vc.type, CheckInType.routine);
      expect(vc.clinicianName, 'Dr. Smith');
      expect(vc.durationMinutes, 15);
      expect(vc.status, CheckInStatus.completed);
      expect(vc.moodLabel, 'Good');
      expect(vc.summary, 'All vitals normal.');
    });

    test('stores startedAt and nextCheckIn dates', () {
      final vc = _basic();
      expect(vc.startedAt, DateTime(2025, 12, 4, 10, 30));
      expect(vc.nextCheckIn, DateTime(2025, 12, 11));
    });

    test('stores followUp type', () {
      final vc = VirtualCheckIn(
        id: 'vc-2',
        type: CheckInType.followUp,
        clinicianName: 'Dr. Jones',
        startedAt: DateTime(2025, 12, 5),
        durationMinutes: 10,
        status: CheckInStatus.missed,
        moodLabel: 'Fair',
        nextCheckIn: DateTime(2025, 12, 12),
        summary: 'Follow-up missed.',
      );
      expect(vc.type, CheckInType.followUp);
      expect(vc.status, CheckInStatus.missed);
    });

    test('stores urgent type with cancelled status', () {
      final vc = VirtualCheckIn(
        id: 'vc-3',
        type: CheckInType.urgent,
        clinicianName: 'Dr. Lee',
        startedAt: DateTime(2025, 12, 6),
        durationMinutes: 5,
        status: CheckInStatus.cancelled,
        moodLabel: 'Poor',
        nextCheckIn: DateTime(2025, 12, 7),
        summary: 'Cancelled by patient.',
      );
      expect(vc.type, CheckInType.urgent);
      expect(vc.status, CheckInStatus.cancelled);
      expect(vc.moodLabel, 'Poor');
      expect(vc.durationMinutes, 5);
    });

    test('stores clinician name correctly', () {
      final vc = _basic();
      expect(vc.clinicianName, 'Dr. Smith');
    });
  });
}
