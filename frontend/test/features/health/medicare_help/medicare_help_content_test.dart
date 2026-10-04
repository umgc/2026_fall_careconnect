// WBS 6.4.33: Medicare help content and in-app guidance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/medicare-help/medicare_help_content.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Future<AppLocalizations> _l10n(WidgetTester tester) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(_app(Builder(builder: (context) {
    l10n = AppLocalizations.of(context)!;
    return const SizedBox.shrink();
  })));
  return l10n;
}

void main() {
  group('Medicare help content (6.4.33)', () {
    testWidgets('every topic has a heading and body text', (tester) async {
      final l10n = await _l10n(tester);
      for (final topic in MedicareHelpTopic.values) {
        final text = medicareHelpText(l10n, topic);
        expect(text.title, isNotEmpty, reason: '$topic title');
        expect(text.body, isNotEmpty, reason: '$topic body');
      }
    });

    testWidgets('error messages use the exact SRS 8.6 text', (tester) async {
      final l10n = await _l10n(tester);
      expect(medicareErrorMessage(l10n, 'ERR-MCR-01'),
          "We couldn't reach Medicare. Try connecting again in a few minutes.");
      expect(medicareErrorMessage(l10n, 'ERR-MCR-02'),
          "Medicare couldn't complete the connection. Try connecting again.");
      expect(medicareErrorMessage(l10n, 'ERR-MCR-03'),
          "Showing your saved records. We couldn't check Medicare for updates.");
      expect(medicareErrorMessage(l10n, 'ERR-MCR-04'),
          'You need an internet connection to connect your Medicare account.');
      expect(medicareErrorMessage(l10n, 'ERR-MCR-05'),
          'Your Medicare connection has expired. Connect again to see current records.');
      expect(medicareErrorMessage(l10n, 'ERR-MCR-99'), isNull);
      expect(medicareErrorMessage(l10n, ''), isNull);
    });

    testWidgets('the connected confirmation matches FR-MCR-04', (tester) async {
      final l10n = await _l10n(tester);
      expect(l10n.medicarehelp_connected, 'Medicare account connected');
    });

    testWidgets(
        'a help card shows its topic with the heading marked as a heading',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _app(const MedicareHelpCard(topic: MedicareHelpTopic.disconnect)));

      expect(find.text('Disconnecting Medicare'), findsOneWidget);
      expect(find.textContaining('You can disconnect at any time.'),
          findsOneWidget);
      expect(
        tester.getSemantics(find.text('Disconnecting Medicare')),
        isSemantics(label: 'Disconnecting Medicare', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the help list shows every topic under one heading',
        (tester) async {
      final l10n = await _l10n(tester);
      await tester.pumpWidget(_app(const MedicareHelpList()));

      expect(find.text('Help with Medicare'), findsOneWidget);
      for (final topic in MedicareHelpTopic.values) {
        final title = medicareHelpText(l10n, topic).title;
        await tester.scrollUntilVisible(find.text(title), 200);
        expect(find.text(title), findsOneWidget, reason: '$topic');
      }
    });

    testWidgets('the help list fits at 200% text size without overflow',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_app(const MedicareHelpList()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Help with Medicare'), findsOneWidget);
    });

    testWidgets('a locale without translations falls back to readable text',
        (tester) async {
      await tester.pumpWidget(_app(
        const MedicareHelpCard(topic: MedicareHelpTopic.connect),
        locale: const Locale('es'),
      ));
      final title = tester.widget<Text>(find.byType(Text).first).data;
      expect(title, isNotNull);
      expect(title, isNotEmpty);
    });
  });
}
