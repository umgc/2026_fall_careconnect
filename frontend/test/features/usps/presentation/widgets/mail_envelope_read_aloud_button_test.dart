import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_envelope_read_aloud_button.dart';

class _FakeTts implements MailEnvelopeTts {
  final List<String> spoken = <String>[];
  final List<String> sessions = <String>[];
  int stopCount = 0;
  Completer<void>? speakGate;
  final ValueNotifier<MailTtsSessionState> _session =
      ValueNotifier(MailTtsSessionState.idle);

  @override
  ValueListenable<MailTtsSessionState> get sessionListenable => _session;

  @override
  String? get activeSessionId => _session.value.activeSessionId;

  @override
  bool get isSpeaking => _session.value.isSpeaking;

  @override
  Future<void> speak(String sessionId, String text) async {
    // Preempt any prior session (mirrors FlutterMailEnvelopeTts).
    if (_session.value.isSpeaking) {
      stopCount++;
      speakGate?.complete();
      speakGate = null;
    }
    spoken.add(text);
    sessions.add(sessionId);
    _session.value = MailTtsSessionState(
      activeSessionId: sessionId,
      isSpeaking: true,
    );
    final gate = speakGate;
    if (gate != null) {
      await gate.future;
    }
    if (_session.value.activeSessionId == sessionId) {
      _session.value = MailTtsSessionState.idle;
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    speakGate?.complete();
    _session.value = MailTtsSessionState.idle;
  }

  @override
  Future<void> dispose() async {
    _session.dispose();
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(() {
    MailEnvelopeTtsService.debugResetInstance();
  });

  testWidgets('start speaks envelope sender and summary', (tester) async {
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
    expect(find.text('Start'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.spoken, ['From: Acme Bank. Monthly statement.']);
  });

  testWidgets('start includes missing-image note when set', (tester) async {
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

  testWidgets('start then stop clears speaking state', (tester) async {
    final fake = _FakeTts()..speakGate = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        MailEnvelopeReadAloudButton(
          sender: 'CVS',
          summary: 'Rx ready',
          tts: fake,
          sessionId: 'btn-a',
        ),
      ),
    );

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.stopCount, greaterThanOrEqualTo(1));
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('two buttons share a single session — second preempts first',
      (tester) async {
    final fake = _FakeTts()..speakGate = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            MailEnvelopeReadAloudButton(
              key: const Key('btn1'),
              sender: 'A',
              summary: 'One',
              tts: fake,
              sessionId: 's1',
            ),
            MailEnvelopeReadAloudButton(
              key: const Key('btn2'),
              sender: 'B',
              summary: 'Two',
              tts: fake,
              sessionId: 's2',
            ),
          ],
        ),
      ),
    );

    final startButtons = find.text('Start');
    expect(startButtons, findsNWidgets(2));

    await tester.tap(find.descendant(
      of: find.byKey(const Key('btn1')),
      matching: find.byKey(MailEnvelopeReadAloudButton.buttonKey),
    ));
    await tester.pump();
    expect(fake.sessions, ['s1']);
    expect(find.text('Stop'), findsOneWidget);

    // Complete first speak so second can start cleanly via speak() stop+speak.
    fake.speakGate?.complete();
    fake.speakGate = Completer<void>();
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byKey(const Key('btn2')),
      matching: find.byKey(MailEnvelopeReadAloudButton.buttonKey),
    ));
    await tester.pump();

    expect(fake.sessions.last, 's2');
    expect(fake.activeSessionId, 's2');
    // Only the active button shows Stop.
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('natural completion resets button to Start', (tester) async {
    final fake = _FakeTts();

    await tester.pumpWidget(
      _wrap(
        MailEnvelopeReadAloudButton(
          sender: 'Lab',
          summary: 'Results',
          tts: fake,
          sessionId: 'done',
        ),
      ),
    );

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Start'), findsOneWidget);
    expect(fake.isSpeaking, isFalse);
  });

  testWidgets('dispose while speaking stops TTS', (tester) async {
    final fake = _FakeTts()..speakGate = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        MailEnvelopeReadAloudButton(
          sender: 'Lab',
          summary: 'Results',
          tts: fake,
        ),
      ),
    );

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    expect(fake.stopCount, greaterThanOrEqualTo(1));
  });

  testWidgets('semantics labels for start and stop', (tester) async {
    final fake = _FakeTts()..speakGate = Completer<void>();
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          MailEnvelopeReadAloudButton(
            sender: 'Post',
            summary: 'Card',
            tts: fake,
          ),
        ),
      );

      expect(find.bySemanticsLabel(RegExp(r'Start reading mail aloud')),
          findsOneWidget);

      await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp(r'Stop reading')), findsOneWidget);

      fake.speakGate?.complete();
    } finally {
      handle.dispose();
    }
  });
}
