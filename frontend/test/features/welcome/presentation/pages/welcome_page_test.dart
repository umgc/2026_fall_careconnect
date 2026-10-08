// Tests for WelcomePage — the app entry screen with backend health check.
// The page makes a real HTTP call in initState with a 5-second timeout and
// a 2-second loading delay (finally block) after that.
// pumpAndSettle() alone does NOT advance the fake clock far enough to trigger
// those timers. Instead we use pump(7s) to advance past both delays, then
// pump() to process the resulting frame rebuilds.
//
// "Initial loading state" tests check the first frame, then drain both timers
// (pump(6s) for the 5s timeout, pump(3s) for the 2s finally delay) to prevent
// "Timer still pending after widget tree disposed" assertion failures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/welcome/presentation/pages/welcome_page.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  // LocaleProvider and AppLocalizations are required by WelcomePage.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

// Advances fake clock past the 5-second HTTP timeout and the 2-second finally delay.
Future<void> _advancePastHealthCheck(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 7));
  await tester.pump(); // process setState() rebuilds
}

// WelcomePage uses a Column that overflows the 600px default test height.
// Set a taller viewport so RenderFlex overflow assertions don't fail the tests.
void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('WelcomePage – initial loading state', () {
    testWidgets('shows CareConnect brand name', (tester) async {
      // The brand name is hardcoded and always visible.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(find.text('CareConnect'), findsOneWidget);
      // Drain the 5s health-check timeout and 2s finally delay to prevent
      // "Timer still pending after widget tree disposed" failures.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows subtitle text', (tester) async {
      // "Connecting Care, Empowering Health" is shown below the logo.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(find.text('Connecting Care, Empowering Health'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows description text', (tester) async {
      // "Your healthcare companion for" is shown as the description.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(find.text('Your healthcare companion for'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows tagline text', (tester) async {
      // "Better Care • Better Outcomes • Better Life" is the app tagline.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(
        find.text('Better Care • Better Outcomes • Better Life'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows loading spinner during health check', (tester) async {
      // Before the health check completes, a CircularProgressIndicator is shown.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump(); // one frame: _isLoading = true
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows Initializing healthcare experience text', (tester) async {
      // The loading message from AppLocalizations is shown during health check.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(
        find.text('Initializing your healthcare experience...'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });

    testWidgets('shows language picker button', (tester) async {
      // The language selector is visible from the start of the page.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      expect(find.byIcon(Icons.language), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    });
  });

  group('WelcomePage – ready state (after health check times out)', () {
    testWidgets('shows Ready to connect text after health check', (tester) async {
      // pump(7s) advances past the 5s HTTP timeout and 2s finally delay.
      // _isLoading becomes false; the ready state is rendered.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.text('Ready to connect your care!'), findsOneWidget);
    });

    testWidgets('shows Continue button after health check', (tester) async {
      // The "Continue" button is only rendered after _isLoading = false.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('no longer shows loading spinner after health check', (tester) async {
      // After _isLoading = false, the spinner is gone from the ready state.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('WelcomePage – compliance badges', () {
    testWidgets('shows HIPAA Compliant badge', (tester) async {
      // The HIPAA compliance badge is rendered in the footer (always present).
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.textContaining('HIPAA'), findsOneWidget);
    });

    testWidgets('shows WCAG AA badge', (tester) async {
      // The WCAG accessibility badge is rendered in the footer.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.textContaining('WCAG'), findsOneWidget);
    });

    testWidgets('shows Secure badge', (tester) async {
      // The security badge is rendered in the footer.
      _setLargeViewport(tester);
      await tester.pumpWidget(_wrap(const WelcomePage()));
      await tester.pump();
      await _advancePastHealthCheck(tester);
      expect(find.textContaining('Secure'), findsOneWidget);
    });
  });
}
