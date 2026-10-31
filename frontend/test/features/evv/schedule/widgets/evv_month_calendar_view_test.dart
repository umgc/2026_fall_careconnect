import 'package:care_connect_app/features/evv/schedule/widgets/evv_month_calendar_view.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _calendar(Locale locale) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: EVVMonthCalendarView(
      visits: const [], selectedDate: DateTime(2026, 6, 1),
    )),
  );
}

void main() {
  testWidgets('places Monday June 1 in the Monday column', (tester) async {
    await tester.pumpWidget(_calendar(const Locale('en')));
    final monday = tester.getCenter(find.text('Mon')).dx;
    final tuesday = tester.getCenter(find.text('Tue')).dx;
    final firstDay = tester.getCenter(find.text('1')).dx;
    final halfColumn = (tuesday - monday) / 2;
    expect(firstDay, inInclusiveRange(monday - halfColumn, monday + halfColumn));
  });

  testWidgets('displays the month and empty state in Spanish', (tester) async {
    await tester.pumpWidget(_calendar(const Locale('es')));
    expect(find.textContaining('junio'), findsOneWidget);
    expect(find.text('No hay visitas programadas'), findsOneWidget);
  });
}
