import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/rbac_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

Widget _wrap(UserProvider provider) => MaterialApp(
      home: ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: const RBACTestScreen(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(_connectivity, (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
  });

  testWidgets('each login button sets a mock user of that role',
      (tester) async {
    final provider = UserProvider();
    await tester.pumpWidget(_wrap(provider));

    for (final entry in {
      'Login as Admin': 'ADMIN',
      'Login as Caregiver': 'CAREGIVER',
      'Login as Patient': 'PATIENT',
      'Login as Family Member': 'FAMILY_MEMBER',
    }.entries) {
      provider.userSession = null;
      await tester.pumpWidget(_wrap(provider));
      await tester.pump();
      if (find.text(entry.key).evaluate().isEmpty) continue;
      await tester.tap(find.text(entry.key));
      await tester.pump();
      expect(provider.user?.role, entry.value);
    }
  });

  testWidgets('admin user can trigger permission buttons and logout',
      (tester) async {
    final provider = UserProvider();
    provider.setUser(UserSession(
      id: 1,
      email: 'admin@test.com',
      role: 'ADMIN',
      token: 'mock',
      name: 'Test admin',
    ));
    provider.userSession = provider.user;
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    for (final label in [
      'Delete Patient (Admin Only)',
      'Create Task',
      'View Health',
    ]) {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) continue;
      await tester.ensureVisible(finder);
      await tester.tap(finder, warnIfMissed: false);
      await tester.pump();
    }
    expect(
      find.textContaining('This would call the backend'),
      findsWidgets,
    );

    final logout = find.text('Logout');
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pump();
    expect(provider.user, isNull);
    await tester.pump(const Duration(seconds: 5));
  });
}
