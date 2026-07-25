// E2E-style ADA envelope readout flow (Task 3.14.10 / #127).
//
// Runs under the unit-test VM (no emulator / Developer Mode required).
// Companion device E2E lives at:
//   integration_test/ada_mail_envelope_readout_e2e_test.dart
//
// OFFLINE: no backend needed

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/usps/domain/mail_envelope_readout_text.dart';
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

class _EnvelopeMailTileHarness extends StatelessWidget {
  const _EnvelopeMailTileHarness({
    required this.sender,
    required this.summary,
    this.missingImage = false,
  });

  final String sender;
  final String summary;
  final bool missingImage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informed Delivery')),
      body: Card(
        child: ListTile(
          leading: MailPieceImage(
            imageRef: missingImage ? null : null,
            sender: sender,
            summary: summary,
          ),
          title: Text(sender),
          subtitle: Text(summary),
          trailing: MailEnvelopeReadAloudButton(
            sender: sender,
            summary: summary,
            includeMissingImageNote: missingImage,
          ),
        ),
      ),
    );
  }
}

void main() {
  tearDown(() {
    MailEnvelopeTtsService.debugResetInstance();
  });

  group('ADA mail envelope readout E2E (Task 3.14.10)', () {
    testWidgets(
      'mail tile read-aloud speaks envelope sender and summary end-to-end',
      (tester) async {
        final fake = _E2eFakeTts();
        MailEnvelopeTtsService.debugSetInstance(fake);

        await tester.pumpWidget(
          const MaterialApp(
            home: _EnvelopeMailTileHarness(
              sender: 'Acme Bank',
              summary: 'Monthly statement',
            ),
          ),
        );

        await tester.tap(find.byKey(MailEnvelopeReadAloudButton.buttonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(fake.spoken, ['From: Acme Bank. Monthly statement.']);
      },
    );

    testWidgets(
      'missing image note is included when flagged',
      (tester) async {
        final fake = _E2eFakeTts();
        MailEnvelopeTtsService.debugSetInstance(fake);

        await tester.pumpWidget(
          const MaterialApp(
            home: _EnvelopeMailTileHarness(
              sender: 'Hospital',
              summary: 'Statement',
              missingImage: true,
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
      },
    );

    testWidgets(
      'read-aloud control exposes start semantics',
      (tester) async {
        final fake = _E2eFakeTts();
        MailEnvelopeTtsService.debugSetInstance(fake);
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            const MaterialApp(
              home: _EnvelopeMailTileHarness(
                sender: 'Hospital Billing',
                summary: 'Statement available',
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.bySemanticsLabel(RegExp(r'Start reading mail aloud')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.volume_up), findsOneWidget);
        } finally {
          handle.dispose();
        }
      },
    );
  });
}
