// Tests for SkeletonPlaybackWidget from
// lib/features/fall_alert/pages/skeleton_playback_widget.dart.
// _parseAndLoadData() is wrapped in try/catch.
// With empty sampleResponse, catch runs → _isLoading=false.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/fall_alert/pages/skeleton_playback_widget.dart';

Widget _wrap() => MaterialApp(
      home: Scaffold(
        body: SkeletonPlaybackWidget(
          sampleResponse: const {},
        ),
      ),
    );

void main() {
  group('SkeletonPlaybackWidget – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SkeletonPlaybackWidget), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error icon when sampleResponse is empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // _parseAndLoadData() catches the error, _isLoading=false, _frames empty → error icon
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator after parse error',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows Center widget for error state', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('shows Icon widget in error state', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Icon), findsOneWidget);
    });
  });
}
