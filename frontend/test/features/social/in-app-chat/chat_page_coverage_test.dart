// ChatPage extras: back navigation, sending from the composer and opening
// the AI chat sheet from the AI Service dialog.

import 'package:care_connect_app/features/social/in-app-chat/pages/chat-page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

Widget _host() => ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChatPage(
                    contactName: 'Dr. Smith',
                    contactRole: 'Doctor',
                  ),
                ),
              ),
              child: const Text('open chat'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host());
  await tester.tap(find.text('open chat'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back arrow returns to the previous page', (tester) async {
    await _open(tester);
    expect(find.text('Dr. Smith'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('open chat'), findsOneWidget);
  });

  testWidgets('sent text appears in the conversation', (tester) async {
    await _open(tester);
    expect(
      find.textContaining('medication is working well'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'See you Monday');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('See you Monday'), findsOneWidget);
  });

  testWidgets('AI Service dialog opens the AI chat sheet', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    await _open(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Service'));
    await tester.pumpAndSettle();
    expect(find.text('Would you like to open the AI chat assistant?'),
        findsOneWidget);
    await tester.tap(find.text('Open AI Chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AIChat), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
