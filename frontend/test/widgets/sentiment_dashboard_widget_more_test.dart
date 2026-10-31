// More happy-path tests for SentimentDashboardWidget
// (lib/widgets/sentiment_dashboard_widget.dart): dark theme, muted channels,
// a multi-point history drawn as a line chart, and the empty detail view.
import 'package:care_connect_app/widgets/sentiment_dashboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Map<String, dynamic> data, {bool dark = false}) => MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SentimentDashboardWidget(callId: 'c1', sentimentData: data),
        ),
      ),
    );

Map<String, dynamic> _payload(double v, double voice, {String? label}) => {
      'text': {'score': v, 'status': 'COMPLETED', 'label': label},
      'voice': {
        'score': voice,
        'status': 'COMPLETED',
        'notes': 'level=0.1 speech=0.2 var=0.3',
      },
      'video': {'score': v, 'status': 'COMPLETED', 'label': label},
      'overall': {'score': v, 'status': 'COMPLETED'},
    };

void main() {
  for (final dark in [false, true]) {
    testWidgets('a growing history draws the chart (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const {}, dark: dark));
      final scores = [0.1, 0.5, 0.9, 0.2, 0.7, 0.4];
      for (final s in scores) {
        await tester.pumpWidget(
            _app(_payload(s, 1 - s, label: s > 0.5 ? 'CALM' : null),
                dark: dark));
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(find.text('VIDEO'), findsOneWidget);

      await tester.tap(find.text('VIDEO'));
      await tester.pumpAndSettle();
      expect(find.text('VIDEO Sentiment'), findsOneWidget);
      expect(find.text('Score History'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('VOICE'));
      await tester.pumpAndSettle();
      expect(find.text('Speech activity 20%, mic level 10%, variability 30%.'),
          findsWidgets);
    });
  }

  testWidgets('muted channels show a banner in dark mode', (tester) async {
    await tester.pumpWidget(_app({
      'voice': {'score': 0.2, 'status': 'MUTED'},
      'video': {'score': 0.2, 'status': 'muted', 'notes': 'off'},
      'overall': {'score': 0.2},
    }, dark: true));
    await tester.pump();
    expect(find.text('Voice: Channel Muted'), findsOneWidget);
    expect(find.text('Video: Channel Muted'), findsOneWidget);
  });

  testWidgets('muted channels show a banner in light mode', (tester) async {
    await tester.pumpWidget(_app({
      'voice': {'score': 0.5, 'status': 'MUTED'},
      'video': {'status': 'PENDING'},
    }));
    await tester.pump();
    expect(find.text('Voice: Channel Muted'), findsOneWidget);
  });

  testWidgets('a channel without data opens an empty detail view',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const {}, dark: true));
    await tester.tap(find.text('VIDEO'));
    await tester.pumpAndSettle();
    expect(find.text('VIDEO Sentiment'), findsOneWidget);
  });

  testWidgets('voice notes with unparseable metrics fall back',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const {}));
    await tester.pumpWidget(_app({
      'voice': {'score': 0.3, 'notes': 'level=. speech=1 var=1'},
      'video': {'score': 0.3, 'status': 'FAILED'},
    }));
    await tester.pump();
    await tester.tap(find.text('VOICE'));
    await tester.pumpAndSettle();
    expect(find.text('VOICE Sentiment'), findsOneWidget);
  });
}
