// Tests for CommunicationTestPage
// (lib/features/communication/presentation/pages/communication_test_page.dart).
//
// Pure StatelessWidget — no Provider, no HTTP. Uses CommunicationWidget
// which initializes services synchronously (service calls are commented out).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/communication/presentation/pages/communication_test_page.dart';

Widget _wrap() => const MaterialApp(home: CommunicationTestPage());

void main() {
  group('CommunicationTestPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CommunicationTestPage), findsOneWidget);
    });

    testWidgets('shows "Communication Test" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Communication Test'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Communication Features Test" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Communication Features Test'), findsOneWidget);
    });

    testWidgets('shows Communication Test title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Communication Test'), findsOneWidget);
    });

    testWidgets('shows Column layout', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('shows SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });
}
