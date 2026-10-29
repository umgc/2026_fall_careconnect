// Tests for CaregiverDashboard
// (lib/features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart).
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('shows the dashboard header with the signed-in caregiver',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
          mockUser: MockUser(
              id: 1,
              name: 'Casey Caregiver',
              role: 'CAREGIVER',
              caregiverId: 42),
        ),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CaregiverDashboard(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }, () => MockClient((_) async => http.Response(jsonEncode([]), 200)));

    final header =
        tester.widget<DashboardAppHeader>(find.byType(DashboardAppHeader));
    expect(header.userName, 'Casey Caregiver');
    expect(header.role, 'CAREGIVER');
  });
}
