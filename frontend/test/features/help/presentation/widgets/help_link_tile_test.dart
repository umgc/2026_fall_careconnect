// Widget tests for lib/features/help/presentation/widgets/help_link_tile.dart.
import 'package:care_connect_app/features/help/presentation/widgets/help_link_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  testWidgets('shows the title and summary and reports a tap', (tester) async {
    var taps = 0;
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
        body: HelpLinkTile(
          title: 'Resetting your password',
          summary: 'Get back into your account.',
          hint: 'Opens a Help article',
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('Resetting your password'), findsOneWidget);
    expect(find.text('Get back into your account.'), findsOneWidget);

    await tester.tap(find.text('Resetting your password'));
    expect(taps, 1);
  });

  testWidgets('without a summary there is no subtitle', (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
        body: HelpLinkTile(title: 'Only a title', hint: 'h', onTap: () {}),
      ),
    );
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.subtitle, isNull);
  });

  testWidgets('is one button with its hint for screen readers, 48 dp tall',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
        body: HelpLinkTile(
            title: 'Viewing appointments',
            hint: 'Opens a Help article',
            onTap: () {}),
      ),
    );
    expect(
      tester.getSemantics(find.text('Viewing appointments')),
      isSemantics(
        label: 'Viewing appointments',
        hint: 'Opens a Help article',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
        tester.getSize(find.byType(ListTile)).height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('shows a focus outline when focused', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
        body: HelpLinkTile(
            title: 'Focus me', hint: 'h', onTap: () {}, focusNode: focus),
      ),
    );
    ShapeBorder? border() =>
        tester.widget<ListTile>(find.byType(ListTile)).shape;
    expect(
        (border()! as RoundedRectangleBorder).side.color, Colors.transparent);

    // Focus outlines show for keyboard users, so move focus with Tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect((border()! as RoundedRectangleBorder).side.color,
        isNot(Colors.transparent));
  });
}
