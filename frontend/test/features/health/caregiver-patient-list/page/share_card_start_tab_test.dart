import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'read') return null;
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    ApiService.debugSetHttpClient(
      MockClient((_) async => http.Response('{}', 200)),
    );
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  for (final entry in {
    'health': 2,
    'medicare': 5,
  }.entries) {
    testWidgets('starts on the ${entry.key} tab', (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider<UserProvider>.value(
              value: MockUserProvider(
                mockUser: MockUser(role: 'CAREGIVER', caregiverId: 7),
              ),
              child: MaterialApp(
                home: PatientDetailsPage(
                  patientId: '42',
                  isCaregiver: true,
                  initialTab: entry.key,
                ),
              ),
            ),
          );
        },
        () => MockClient((_) async => http.Response('{}', 200)),
      );

      final controller =
          tester.widget<DefaultTabController>(find.byType(DefaultTabController));
      expect(controller.initialIndex, entry.value);
    });
  }
}
