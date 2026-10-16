import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/activities/presentation/pages/adl_iadl_management_screen.dart';

void main() {
  Widget buildScreen({int clientId = 1, String clientName = 'Alice Smith'}) {
    return MaterialApp(
      home: AdlIadlManagementScreen(
        clientId: clientId,
        clientName: clientName,
      ),
    );
  }

  group('AdlIadlManagementScreen', () {
    testWidgets('renders AppBar with correct title', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('ADL & IADL Management'), findsOneWidget);
    });

    testWidgets('renders client name in AppBar subtitle', (tester) async {
      await tester.pumpWidget(buildScreen(clientName: 'Bob Jones'));
      expect(find.text('Bob Jones'), findsOneWidget);
    });

    testWidgets('renders ADL Activities entry card', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('ADL Activities'), findsOneWidget);
    });

    testWidgets('renders IADL Activities entry card', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('IADL Activities'), findsOneWidget);
    });

    testWidgets('renders Activity log history entry card', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Activity log history'), findsOneWidget);
    });

    testWidgets('renders subtitle for ADL card', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Log and manage Activities of Daily Living'), findsOneWidget);
    });

    testWidgets('renders subtitle for IADL card', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(
        find.text('Log and manage Instrumental Activities of Daily Living'),
        findsOneWidget,
      );
    });

    testWidgets('renders three navigation cards total', (tester) async {
      await tester.pumpWidget(buildScreen());
      // Each card has an InkWell — there are exactly 3 navigation entries
      expect(find.byType(Card), findsNWidgets(3));
    });

    testWidgets('renders chevron_right icons for all cards', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    });

    testWidgets('renders bathtub icon for ADL entry', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.bathtub), findsOneWidget);
    });

    testWidgets('renders soup_kitchen icon for IADL entry', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.soup_kitchen), findsOneWidget);
    });

    testWidgets('renders history icon for log history entry', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('different clientId and clientName render correctly', (tester) async {
      await tester.pumpWidget(buildScreen(clientId: 99, clientName: 'Carol White'));
      expect(find.text('Carol White'), findsOneWidget);
      expect(find.text('ADL & IADL Management'), findsOneWidget);
    });
  });
}
