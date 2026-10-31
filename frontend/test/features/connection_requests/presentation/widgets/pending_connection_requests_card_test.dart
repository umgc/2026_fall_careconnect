import 'package:care_connect_app/features/connection_requests/models/connection_request_summary.dart';
import 'package:care_connect_app/features/connection_requests/presentation/widgets/pending_connection_requests_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/pump_app.dart';

const _request = ConnectionRequestSummary(
  id: 100,
  caregiverName: 'Carey Tester',
  caregiverEmail: 'carey@example.com',
  patientName: 'Index Tester',
  patientEmail: 'index@example.com',
  status: 'PENDING',
  message: 'Happy to help',
);

void main() {
  testWidgets('renders nothing when there are no pending requests', (tester) async {
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(loadRequests: () async => const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caregiver requests'), findsNothing);
  });

  testWidgets('renders nothing when loading fails', (tester) async {
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(loadRequests: () async => throw Exception('offline')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('lists a pending request with its message', (tester) async {
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(loadRequests: () async => const [_request]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Caregiver requests'), findsOneWidget);
    expect(find.textContaining('Carey Tester would like to be your caregiver'), findsOneWidget);
    expect(find.text('"Happy to help"'), findsOneWidget);
  });

  testWidgets('accepting removes the request, confirms, and notifies the dashboard',
      (tester) async {
    // Arrange
    int? accepted;
    var refreshed = false;
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(
        loadRequests: () async => const [_request],
        acceptRequest: (id) async => accepted = id,
        onAccepted: () => refreshed = true,
      ),
    );
    await tester.pumpAndSettle();

    // Act
    await tester.tap(find.byKey(const Key('accept-100')));
    await tester.pumpAndSettle();

    // Assert
    expect(accepted, 100);
    expect(refreshed, isTrue);
    expect(find.text('You are now connected with Carey Tester.'), findsOneWidget);
    expect(find.text('Caregiver requests'), findsNothing);
  });

  testWidgets('declining removes the request without notifying the dashboard',
      (tester) async {
    int? declined;
    var refreshed = false;
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(
        loadRequests: () async => const [_request],
        declineRequest: (id) async => declined = id,
        onAccepted: () => refreshed = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('decline-100')));
    await tester.pumpAndSettle();

    expect(declined, 100);
    expect(refreshed, isFalse);
    expect(find.text('Request declined.'), findsOneWidget);
  });

  testWidgets('a failed answer keeps the request and shows an error', (tester) async {
    await pumpCareConnectApp(
      tester,
      PendingConnectionRequestsCard(
        loadRequests: () async => const [_request],
        acceptRequest: (_) async => throw Exception('server down'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accept-100')));
    await tester.pumpAndSettle();

    expect(find.text('Could not update the request. Please try again.'), findsOneWidget);
    expect(find.text('Caregiver requests'), findsOneWidget);
  });
}
