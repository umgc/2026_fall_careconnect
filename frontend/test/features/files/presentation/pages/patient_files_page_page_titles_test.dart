// Page-title tests for PatientFilesPage
// (lib/features/files/presentation/pages/patient_files_page.dart): the
// checklist button opens a titled page (WCAG 2.4.2).
import 'package:care_connect_app/features/files/presentation/pages/patient_files_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';
import '../../../../mock_user_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  testWidgets(
      'the checklist button opens a page titled "Compliance Checklist"',
      (tester) async {
    final probe = TitledRouteProbe();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER')),
      child: MaterialApp(
        navigatorObservers: [probe],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const PatientFilesPage(patientId: 1, patientName: 'Jane Doe'),
      ),
    ));
    await tester.pump();
    expect(
        await probe.tapAndReadTitle(
            tester, find.byTooltip('Required documents checklist')),
        'Compliance Checklist');
  });
}
