// Page-title tests for FriendRequestsScreen
// (lib/features/social/presentation/pages/friend_requests_screen.dart): the
// My Friends button opens a titled page (WCAG 2.4.2).
import 'package:care_connect_app/features/social/presentation/pages/friend_requests_screen.dart';
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

  testWidgets('My Friends opens a page titled "My Friends"', (tester) async {
    final probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT')),
        child: const FriendRequestsScreen(),
      ),
    ));
    await tester.pump();
    expect(await probe.tapAndReadTitle(tester, find.byTooltip('My Friends')),
        'My Friends');
  });
}
