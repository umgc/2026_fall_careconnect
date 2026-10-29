// Page-title tests for MyFriendsScreen
// (lib/features/social/presentation/pages/my_friend_screen.dart): opening a
// contact starts a conversation in a titled page (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/features/social/presentation/pages/my_friend_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  testWidgets('a patient opening a caregiver contact pushes "Conversation"',
      (tester) async {
    final probe = TitledRouteProbe();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [probe],
        home: ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(mockUser: MockUser(id: 42, role: 'PATIENT')),
          child: MyFriendsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Casey Caregiver'), findsOneWidget);
      expect(await probe.tapAndReadTitle(tester, find.text('Casey Caregiver')),
          'Conversation');
    },
        () => MockClient((request) async => http.Response(
            jsonEncode([
              {
                'caregiverUserId': 9,
                'caregiverName': 'Casey Caregiver',
                'caregiverEmail': 'casey@example.test',
                'patientMessagingEnabled': true,
              }
            ]),
            200)));
  });
}
