import 'package:care_connect_app/widgets/sentiment_dashboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('SentimentDashboardWidget', () {
    testWidgets('shows awaiting state when sentiment data is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SentimentDashboardWidget(
            sentimentData: {},
            callId: 'call-empty',
          ),
        ),
      );

      expect(find.text('Live Emotional Analysis'), findsOneWidget);
      expect(find.text('Awaiting data...'), findsOneWidget);
      expect(find.text('VOICE'), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.text('OVERALL'), findsOneWidget);
    });

    testWidgets(
        'renders completed and degraded channel states with voice notes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SentimentDashboardWidget(
            callId: 'call-mixed',
            sentimentData: {
              '_captureMode': 'ADAPTIVE_REALTIME',
              'voice': {
                'score': 0.78,
                'status': 'COMPLETED',
                'notes': 'level=0.42 speech=0.86 var=0.15',
              },
              'video': {
                'score': 0.33,
                'status': 'DEGRADED',
                'notes': 'camera paused',
              },
              'overall': {'score': 0.61, 'status': 'COMPLETED'},
            },
          ),
        ),
      );

      expect(find.text('CALM'), findsWidgets);
      expect(
        find.text('Speech activity 86%, mic level 42%, variability 15%.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Insights are briefly paused. Your call is still running normally.',
        ),
        findsOneWidget,
      );
      expect(find.text('DEGRADED'), findsOneWidget);
    });

    testWidgets('opens detail view with history after sentiment updates', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SentimentDashboardWidget(
            callId: 'call-history',
            sentimentData: {},
          ),
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          const SentimentDashboardWidget(
            callId: 'call-history',
            sentimentData: {
              'voice': {'score': 0.72, 'status': 'COMPLETED', 'notes': 'ok'},
              'video': {'score': 0.41, 'status': 'COMPLETED', 'notes': 'ok'},
              'overall': {'score': 0.56, 'status': 'COMPLETED'},
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('VOICE'));
      await tester.pumpAndSettle();

      expect(find.text('VOICE Sentiment'), findsOneWidget);
      expect(find.text('Score History'), findsOneWidget);
      expect(find.text('CALM'), findsOneWidget);
      expect(
        find.text('Voice activity from raw Chime metrics.'),
        findsOneWidget,
      );
    });
  });
}
