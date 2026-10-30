// Rendering tests for EmailVerificationDialog: the resend button outcomes
// and verification polling, which closes the dialog once the email is
// verified. With realtime enabled the dialog is only closed through the
// verified path here; closing it while the socket is still open is not
// exercised.

import 'package:care_connect_app/widgets/email_verification_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<List<bool?>> _openDialog(WidgetTester tester) async {
  final results = <bool?>[];
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              results.add(await showDialog<bool>(
                context: context,
                builder: (_) =>
                    const EmailVerificationDialog(email: 'pat@example.com'),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return results;
}

void main() {
  group('with realtime disabled', () {
    setUp(() => EmailVerificationDialog.debugDisableRealtime = true);
    tearDown(() => EmailVerificationDialog.debugDisableRealtime = false);

    MockClient resend(int status, {Object? error}) =>
        MockClient((request) async {
          if (error != null) throw error;
          return http.Response('{}', status);
        });

    testWidgets('resend success shows a confirmation', (tester) async {
      await http.runWithClient(() async {
        await _openDialog(tester);
        expect(find.text('pat@example.com'), findsOneWidget);
        expect(find.text('Connecting...'), findsOneWidget);
        await tester.tap(find.text('Resend Email'));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Verification email sent successfully!'),
          findsOneWidget,
        );
      }, () => resend(200));
    });

    testWidgets('resend failure shows an error', (tester) async {
      await http.runWithClient(() async {
        await _openDialog(tester);
        await tester.tap(find.text('Resend Email'));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Failed to send verification email. Please try again.'),
          findsOneWidget,
        );
      }, () => resend(500));
    });

    testWidgets('resend network errors are reported', (tester) async {
      await http.runWithClient(() async {
        await _openDialog(tester);
        await tester.tap(find.text('Resend Email'));
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining('Error sending verification email'),
          findsOneWidget,
        );
      }, () => resend(0, error: http.ClientException('offline')));
    });

    testWidgets('close dismisses the dialog', (tester) async {
      final results = await _openDialog(tester);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailVerificationDialog), findsNothing);
      expect(results, [null]);
    });
  });

  group('with realtime enabled', () {
    testWidgets('polling closes the dialog once the email is verified',
        (tester) async {
      var checks = 0;
      final client = MockClient((request) async {
        checks++;
        return http.Response(
          checks < 2 ? '{"verified": false}' : '{"verified": true}',
          200,
        );
      });
      await http.runWithClient(() async {
        final results = await _openDialog(tester);
        expect(find.byType(EmailVerificationDialog), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(
          find.text('Email verified successfully! You can now log in.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.byType(EmailVerificationDialog), findsNothing);
        expect(results, [true]);
      }, () => client);
    });
  });
}
