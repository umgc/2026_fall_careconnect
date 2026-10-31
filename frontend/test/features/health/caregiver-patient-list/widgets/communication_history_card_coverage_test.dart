// Additional coverage for CommunicationHistoryCard: multi-event call
// aggregation, final sentiment badges, sentiment colors, metadata parsing
// and the interactive (onCallTap) trailing layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/communication_history_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('aggregates multiple events per call and keeps first final',
      (tester) async {
    final events = <Map<String, dynamic>>[
      {
        'callId': 'chime-call-ABCD1234',
        'occurredAt': '2025-01-01T10:00:00Z',
        'eventType': 'CALL_JOIN',
      },
      {
        'callId': 'chime-call-ABCD1234',
        'occurredAt': '2025-01-01T10:05:00Z',
        'eventType': 'SENTIMENT_SAMPLE',
        'sentimentLabel': 'neutral',
        'sentimentScore': 0.4,
      },
      {
        'callId': 'chime-call-ABCD1234',
        'occurredAt': '2025-01-01T10:10:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'POSITIVE',
        'sentimentScore': 0.9,
      },
      // Later event after a final: final values are preserved; older date
      // keeps the existing lastOccurredAt.
      {
        'callId': 'chime-call-ABCD1234',
        'occurredAt': '2025-01-01T09:00:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'NEGATIVE',
        'sentimentScore': 0.1,
      },
    ];

    await tester.pumpWidget(_wrap(CommunicationHistoryCard(events: events)));

    expect(find.text('1 calls recorded'), findsOneWidget);
    expect(find.text('Telehealth call #1234'), findsOneWidget);
    expect(find.textContaining('Accepted - 3 sentiment samples'),
        findsOneWidget);
    expect(find.text('90.0% POSITIVE'), findsOneWidget);
    expect(_colorOf(tester, '90.0% POSITIVE'), Colors.green.shade700);
  });

  testWidgets('final label only, score only and colors per label',
      (tester) async {
    final events = <Map<String, dynamic>>[
      {
        'callId': 'call-1111',
        'occurredAt': '2025-01-04T10:00:00Z',
        'eventType': 'WS_DECLINE_CALL',
      },
      {
        'callId': 'call-1111',
        'occurredAt': '2025-01-04T10:01:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'ANXIOUS',
      },
      {
        'callId': 'call-2222',
        'occurredAt': '2025-01-03T10:00:00Z',
        'eventType': 'WS_END_CALL',
      },
      {
        'callId': 'call-2222',
        'occurredAt': '2025-01-03T10:01:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentScore': 0.25,
      },
      {
        'callId': 'call-3333',
        'occurredAt': '2025-01-02T10:00:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'NEUTRAL',
        'sentimentScore': 0.5,
      },
      {
        'callId': 'call-4444',
        'occurredAt': '2025-01-01T10:00:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'MYSTERY',
      },
    ];

    await tester.pumpWidget(_wrap(CommunicationHistoryCard(events: events)));

    expect(find.text('4 calls recorded'), findsOneWidget);
    expect(find.textContaining('Rejected'), findsOneWidget);
    expect(find.textContaining('Ended'), findsOneWidget);
    expect(find.text('ANXIOUS'), findsOneWidget);
    expect(_colorOf(tester, 'ANXIOUS'), Colors.red.shade700);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('50.0% NEUTRAL'), findsOneWidget);
    expect(_colorOf(tester, '50.0% NEUTRAL'), Colors.amber.shade800);
    expect(find.text('MYSTERY'), findsOneWidget);
    expect(_colorOf(tester, 'MYSTERY'), isNotNull);
  });

  testWidgets('care-team calls from map, JSON string and Map metadata',
      (tester) async {
    final events = <Map<String, dynamic>>[
      {
        'callId': 'twilio-call-CT01',
        'occurredAt': '2025-01-02T10:00:00Z',
        'eventType': 'CALL_JOIN',
        'metadataJson': <String, dynamic>{'callKind': 'care_team'},
      },
      {
        'callId': 'call-CT02',
        'occurredAt': '2025-01-01T10:00:00Z',
        'eventType': 'CALL_JOIN',
        'metadataJson': '{"callKind":"CARE_TEAM"}',
      },
      {
        'callId': 'call-CT02',
        'occurredAt': '2025-01-01T10:02:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'CALM',
        'sentimentScore': 0.8,
        'metadataJson': 'not-json{',
      },
      {
        'callId': 'xx',
        'occurredAt': 'garbage-date',
        'eventType': 'OTHER',
        'metadataJson': '[1,2]',
      },
      {'callId': '   '},
    ];

    await tester.pumpWidget(_wrap(CommunicationHistoryCard(events: events)));

    expect(find.text('3 calls recorded'), findsOneWidget);
    expect(find.textContaining('Care-team call'), findsNWidgets(2));
    // Care-team calls never show a sentiment badge.
    expect(find.text('80.0% CALM'), findsNothing);
    // Short IDs fall back to the generic title.
    expect(find.text('Telehealth call'), findsOneWidget);
  });

  testWidgets('interactive mode shows badge + View details and taps',
      (tester) async {
    // The card's decorated Container sits between the ListTile and the
    // Scaffold's Material; drop only that debug report.
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.toString().contains(
          'ListTile background color or ink splashes may be invisible')) {
        return;
      }
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    final tapped = <String>[];
    final events = <Map<String, dynamic>>[
      {
        'callId': 'call-9999',
        'occurredAt': '2025-01-01T10:00:00Z',
        'eventType': 'SENTIMENT_FINAL',
        'sentimentLabel': 'CALM',
        'sentimentScore': 0.75,
      },
    ];

    await tester.pumpWidget(_wrap(CommunicationHistoryCard(
      events: events,
      onCallTap: tapped.add,
    )));

    expect(find.text('75.0% CALM'), findsOneWidget);
    expect(_colorOf(tester, '75.0% CALM'), Colors.green.shade700);
    expect(find.text('View details'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    expect(tapped, ['call-9999']);
  });
}
