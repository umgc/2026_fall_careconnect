import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AI Chat Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Modal AI Chat should show header text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'patient',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );

      await tester.pumpAndSettle();

      // The improved AI Chat shows 'AI Chat' as the header title
      expect(find.text('AI Chat'), findsOneWidget);

      // Should find the smart_toy icon in the header
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    testWidgets('Modal AI Chat should show health assistant elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'caregiver',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );

      await tester.pumpAndSettle();

      // Should show the AI Chat header
      expect(find.text('AI Chat'), findsOneWidget);

      // Should show input field
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Modal AI Chat shows Scaffold', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'patient',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Modal AI Chat shows Column layout',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'patient',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('Modal AI Chat shows send icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'patient',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('Modal AI Chat shows Row layout', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
              body: AIChat(
                  role: 'caregiver',
                  isModal: true,
                  mode: AiChatMode.legacyGeneral)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Row), findsWidgets);
    });
  });
}
