import 'package:care_connect_app/features/evv/schedule/widgets/evv_week_calendar_view.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _calendar(Locale locale, {ValueChanged<DateTime>? onDateSelected}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: EVVWeekCalendarView(
      visits: const [], selectedDate: DateTime(2026, 3, 17),
      onDateSelected: onDateSelected,
    )),
  );
}

void main() {
  testWidgets('displays English empty days and navigates to the next week', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(_calendar(const Locale('en'), onDateSelected: (date) => selected = date));
    expect(find.text('No visits'), findsWidgets);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(selected, DateTime(2026, 3, 23));
  });

  testWidgets('displays Spanish empty days', (tester) async {
    await tester.pumpWidget(_calendar(const Locale('es')));
    expect(find.text('No hay visitas'), findsWidgets);
  });
}
