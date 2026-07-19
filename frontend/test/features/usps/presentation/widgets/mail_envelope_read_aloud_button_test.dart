import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_envelope_read_aloud_button.dart';

class _FakeTts implements MailEnvelopeTts {
  final List<String> spoken = <String>[];
  int stopCount = 0;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(() {
    MailEnvelopeTtsService.debugResetInstance();
  });

  testWidgets('read-aloud button speaks envelope sender and summary',
      (tester) async {
    final fake = _FakeTts();
    MailEnvelopeTtsService.debugSetInstance(fake);

    await tester.pumpWidget(
      _wrap(
        const MailEnvelopeReadAloudButton(
          sender: 'Acme Bank',
          summary: 'Monthly statement',
        ),
      ),
    );

    expect(find.byKey(MailEnvelopeReadAloudButton.buttonKey), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.spoken, ['From: Acme Bank. Monthly statement.']);
  });

  testWidgets('read-aloud button includes missing-image note when set',
      (tester) async {
    final fake = _FakeTts();

    await tester.pumpWidget(
      _wrap(
        MailEnvelopeReadAloudButton(
          sender: 'Hospital',
          summary: 'Statement',
          includeMissingImageNote: true,
          tts: fake,
        ),
      ),
    );

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      fake.spoken.single,
      contains('No envelope image is available'),
    );
  });
}
