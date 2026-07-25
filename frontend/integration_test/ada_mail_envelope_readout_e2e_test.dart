// E2E-style coverage for ADA envelope-level mail audio readout (Task 3.14.10 / #127).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_envelope_read_aloud_button.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_piece_image.dart';

class _E2eFakeTts implements MailEnvelopeTts {
  final List<String> spoken = <String>[];
  int stopCount = 0;
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
    spoken.add(text);
    _session.value = MailTtsSessionState(
      activeSessionId: sessionId,
      isSpeaking: true,
    );
    _session.value = MailTtsSessionState.idle;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _session.value = MailTtsSessionState.idle;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    MailEnvelopeTtsService.debugResetInstance();
  });

  testWidgets('mail tile read-aloud speaks sender and summary', (tester) async {
    final fake = _E2eFakeTts();
    MailEnvelopeTtsService.debugSetInstance(fake);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(
            leading: const MailPieceImage(
              imageRef: null,
              sender: 'Acme',
              summary: 'Bill',
            ),
            title: const Text('Acme'),
            trailing: const MailEnvelopeReadAloudButton(
              sender: 'Acme',
              summary: 'Bill',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
    await tester.pump();
    expect(fake.spoken, isNotEmpty);
  });
}
