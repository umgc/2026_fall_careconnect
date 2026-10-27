// Accessibility test for CurrentMoodWidget: the mood slider has a name (WCAG 4.1.2).
// Setup copied from current_mood_widget_test.dart.
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../../mock_user_provider.dart';
import 'package:flutter/semantics.dart';

/// Forces offline mode so no real HTTP calls are made during tests.
class _OfflineMockUserProvider extends MockUserProvider {
  @override
  bool get isDeviceOnline => false;

  @override
  bool get offlineModeEnabled => true;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: _OfflineMockUserProvider(),
    child: MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child)),
  );
}


void main() {
  testWidgets('the mood slider has a name and reads its value out of 10',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const CurrentMoodWidget(
        moodScore: 7, moodLabel: 'Happy', moodTags: ['Relaxed'])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The name and the value can sit on the slider's node or its children.
    final labels = <String>[];
    final values = <String>[];
    void collect(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.label.isNotEmpty) labels.add(data.label);
      if (data.value.isNotEmpty) values.add(data.value);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(tester.getSemantics(find.byType(Slider)));
    expect(labels, contains(startsWith('Rate how you feel right now:')),
        reason: 'WCAG 4.1.2: the slider needs a name');
    expect(values, contains('7 / 10'));
    handle.dispose();
  });
}
