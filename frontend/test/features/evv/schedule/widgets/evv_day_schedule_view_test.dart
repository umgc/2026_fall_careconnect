import 'package:care_connect_app/features/evv/schedule/widgets/evv_day_schedule_view.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _calendar(Locale locale, {ValueChanged<DateTime>? onDateSelected}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: EVVDayScheduleView(
      visits: const [], selectedDate: DateTime(2026, 3, 17),
      onDateSelected: onDateSelected,
    )),
  );
}

void main() {
  testWidgets('displays the day in English and navigates to the next day', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(_calendar(const Locale('en'), onDateSelected: (date) => selected = date));
    expect(find.textContaining('March 17, 2026'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(selected, DateTime(2026, 3, 18));
  });

  testWidgets('displays the day in Spanish', (tester) async {
    await tester.pumpWidget(_calendar(const Locale('es')));
    expect(find.textContaining('marzo'), findsOneWidget);
  });
}
