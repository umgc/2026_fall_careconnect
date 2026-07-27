// Tests for AIChatModal from lib/widgets/ai_chat_modal.dart.
// Uses Provider.of<UserProvider> in build() to pass user info to AIChat.
// Needs UserProvider; shown as a Dialog.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/ai_chat_modal.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _wrap() {
  final provider = _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => ChangeNotifierProvider<UserProvider>.value(
              value: provider,
              child: const AIChatModal(
                  role: 'patient', mode: AiChatMode.groundedRecords),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  group('AIChatModal – dialog render', () {
    testWidgets('renders without crashing when opened', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byType(AIChatModal), findsOneWidget);
    });

    testWidgets('shows Dialog widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('shows close icon for modal', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsWidgets);
    });

    testWidgets('shows TextField for message input', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows send icon button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('shows hint text in input', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(
        find.text("Ask about this patient's records..."),
        findsOneWidget,
      );
    });

    testWidgets('caregiver modal never infers mutable user.patientId',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          id: 9,
          role: 'CAREGIVER',
          caregiverId: 3,
          patientId: 999,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => ChangeNotifierProvider<UserProvider>.value(
                    value: provider,
                    child: const AIChatModal(
                      role: 'caregiver',
                      mode: AiChatMode.groundedRecords,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();

      final chat = tester.widget<AIChat>(find.byType(AIChat));
      expect(chat.mode, AiChatMode.groundedRecords);
      expect(chat.patientId, isNull);
      expect(chat.patientId, isNot(999));
    });
  });
}
