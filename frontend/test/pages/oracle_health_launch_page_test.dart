import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/pages/oracle_health_launch_page.dart';
import 'package:care_connect_app/services/pending_oracle_health_launch.dart';

void main() {
  group('OracleHealthLaunchPage', () {
    setUp(PendingOracleHealthLaunch.clear);
    tearDown(PendingOracleHealthLaunch.clear);

    testWidgets(
      'displays the provided Oracle Health launch error',
      (tester) async {
        const errorMessage = 'Invalid Oracle Health launch request.';

        await tester.pumpWidget(
          const MaterialApp(
            home: OracleHealthLaunchPage(
              errorMessage: errorMessage,
            ),
          ),
        );

        expect(find.text('Oracle Health Connection'), findsOneWidget);
        expect(find.text(errorMessage), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.text('Preparing Oracle Health connection...'),
          findsNothing,
        );
      },
    );

    testWidgets('starts authorization with the pending launch token',
        (tester) async {
      PendingOracleHealthLaunch.set(
        issuer: 'https://fhir.example.com/r4/test',
        launch: 'temporary-launch',
      );
      String? receivedLaunch;

      await tester.pumpWidget(
        MaterialApp(
          home: OracleHealthLaunchPage(
            authHeadersLoader: () async => {
              'Authorization': 'Bearer careconnect-token',
            },
            connector: ({String? launch}) async {
              receivedLaunch = launch;
            },
          ),
        ),
      );
      await tester.pump();

      expect(receivedLaunch, 'temporary-launch');
      expect(PendingOracleHealthLaunch.hasPending, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error when no pending launch exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OracleHealthLaunchPage(
            authHeadersLoader: () async => {
              'Authorization': 'Bearer careconnect-token',
            },
            connector: ({String? launch}) async {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No pending Oracle Health launch was found.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows a recoverable error when authorization fails',
        (tester) async {
      PendingOracleHealthLaunch.set(
        issuer: 'https://fhir.example.com/r4/test',
        launch: 'temporary-launch',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OracleHealthLaunchPage(
            authHeadersLoader: () async => {
              'Authorization': 'Bearer careconnect-token',
            },
            connector: ({String? launch}) async {
              throw Exception('backend unavailable');
            },
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Unable to start Oracle Health authorization. Please try again.',
        ),
        findsOneWidget,
      );
    });
  });
}
