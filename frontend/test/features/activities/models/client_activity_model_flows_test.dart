// Parsing tests for the activity models
// (lib/features/activities/models/client_activity_model.dart): every
// fromJson is fed both int-typed and string-typed numbers, and both ISO
// strings and Java LocalDateTime arrays for timestamps.

import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _intDate = [2026, 10, 5, 9, 30, 15];
const _strDate = ['2026', '10', '5', '9', '30', '15'];

void main() {
  test('ClientActivity, CompetencyScaleItem and Activity parse', () {
    for (final id in [3, '3']) {
      final ca = ClientActivity.fromJson({
        'id': id,
        'activityId': id,
        'name': 'Bathing',
        'category': 'adl',
        'enabled': true,
        'defaultIconUrl': 'a',
        'customIconUrl': 'b',
      });
      expect(ca.name, 'Bathing');
      final scale = CompetencyScaleItem.fromJson({'value': id, 'label': 'L'});
      expect(scale.label, 'L');
      final act = Activity.fromJson(
          {'id': id, 'name': 'Dressing', 'category': 'ADL'});
      expect(act.name, 'Dressing');
    }
  });

  test('ActivityLogEntry handles string ids and date arrays', () {
    for (final date in [_intDate, _strDate, '2026-10-05T09:30:15']) {
      final e = ActivityLogEntry.fromJson({
        'id': '1',
        'clientId': '2',
        'activityId': '3',
        'activityName': 'Eating',
        'competencyScore': '4',
        'satisfactionRating': '5',
        'notes': 'ok',
        'createdAt': date,
      });
      expect(e.createdAt.year, 2026);
      expect(e.activityId, 3);
    }
  });

  test('BehavioralIncidentEntry parses both date shapes and snake_case', () {
    for (final date in [_intDate, _strDate]) {
      final e = BehavioralIncidentEntry.fromJson({
        'id': '9',
        'clientId': '2',
        'caregiverId': '4',
        'observedBehavior': 'Pacing',
        'occurred_at': date,
        'trigger_notes': 'noise',
      });
      expect(e.occurredAt.month, 10);
      expect(e.id, 9);
    }
    final ints = BehavioralIncidentEntry.fromJson({
      'id': 1,
      'clientId': 2,
      'caregiverId': 3,
      'observed_behavior': 'Yelling',
      'occurredAt': '2026-10-01T00:00:00',
      'triggerNotes': 'x',
    });
    expect(ints.caregiverId, 3);
  });

  test('IncidentReportEntry parses dates, ids and actions', () {
    for (final date in [_intDate, _strDate]) {
      final e = IncidentReportEntry.fromJson({
        'id': '5',
        'clientId': '6',
        'caregiverId': '7',
        'incident_type': 'FALL',
        'occurred_at': date,
        'created_at': date,
        'location': 'Kitchen',
        'trigger_notes': 'wet floor',
        'outcome': 'ok',
        'actions': [
          {'actionTaken': ' Called nurse '},
          'Applied ice',
          {'other': 1},
          '',
        ],
      });
      expect(e.actions, contains('Called nurse'));
      expect(e.actions, contains('Applied ice'));
      expect(e.createdAt.day, 5);
    }
    final ints = IncidentReportEntry.fromJson({
      'id': 1,
      'clientId': 2,
      'caregiverId': 3,
      'incidentType': 'OTHER',
      'occurredAt': '2026-10-01T00:00:00',
      'createdAt': '2026-10-01T00:00:00',
      'triggerNotes': 't',
    });
    expect(ints.incidentType, 'OTHER');
  });

  test('competency, behavioral and participation reports parse', () {
    for (final n in [2, '2']) {
      final comp = CompetencyTrendsResponse.fromJson({
        'weekLabels': ['W1', 'W2'],
        'activityTrends': [
          {
            'activityId': n,
            'activityName': 'Bathing',
            'status': 'IMPROVING',
            'dataPoints': [
              {
                'weekStartDate': '2026-10-01',
                'averageCompetencyScore': n is int ? 3.5 : '3.5',
                'logCount': n,
              },
            ],
          },
        ],
      });
      expect(comp.activityTrends.single.dataPoints.single.weekStartDate,
          '2026-10-01');

      final beh = BehavioralTrendsResponse.fromJson({
        'trend': 'RISING',
        'weeklyCounts': [
          {'weekStartDate': '2026-10-01', 'incidentCount': n},
        ],
        'topKeywords': ['pacing', 'noise'],
      });
      expect(beh.weeklyCounts.single.incidentCount, 2);

      final part = ParticipationResponse.fromJson({
        'status': 'DECLINING',
        'weeklyCounts': [
          {'weekStartDate': '2026-10-01', 'totalLogs': n},
        ],
        'activities': [
          {
            'activityId': n,
            'activityName': 'Laundry',
            'category': 'iadl',
            'totalLogsInPeriod': n,
            'lastLoggedAt': n is int ? _intDate : _strDate,
            'noRecentActivity': true,
          },
          {
            'activityId': n,
            'activityName': 'Shopping',
            'lastLoggedAt': '2026-10-02T10:00:00',
          },
        ],
      });
      expect(part.activities.first.category, 'IADL');
      expect(part.activities.first.lastLoggedAt?.minute, 30);
      expect(part.activities.last.lastLoggedAt?.day, 2);
    }

    // Missing collections fall back to empty lists.
    expect(CompetencyTrendsResponse.fromJson(const {}).activityTrends,
        isEmpty);
    expect(BehavioralTrendsResponse.fromJson(const {}).weeklyCounts, isEmpty);
    expect(ParticipationResponse.fromJson(const {}).activities, isEmpty);
  });
}
