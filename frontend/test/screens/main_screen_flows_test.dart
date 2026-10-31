// Flow tests for MainScreen (lib/screens/main_screen.dart): the global
// quick video-call picker, the unread-messages badge, the voice-command
// flyout callbacks, lifecycle handling and the invalid-session redirect.
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/config/navigation/main_screen_config.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/main_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

/// Canned backend for the endpoints MainScreen touches.
class _Backend {
  Object inbox = const [];
  int inboxStatus = 200;
  Object caregiverPatients = const [];
  int caregiverPatientsStatus = 200;
  Map<int, Object> caregiversByPatient = {};

  void install() {
    ApiService.debugSetHttpClient(MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/messages/inbox/')) {
        return http.Response(jsonEncode(inbox), inboxStatus);
      }
      final cg = RegExp(r'caregiver-patient-links/patients/(\d+)/caregivers')
          .firstMatch(path);
      if (cg != null) {
        final id = int.parse(cg.group(1)!);
        return http.Response(jsonEncode(caregiversByPatient[id] ?? []), 200);
      }
      if (RegExp(r'caregivers/\d+/patients').hasMatch(path)) {
        return http.Response(
            jsonEncode(caregiverPatients), caregiverPatientsStatus);
      }
      return http.Response('[]', 200);
    }));
    addTearDown(ApiService.debugResetHttpClient);
  }
}

MainScreenConfig _config(String role, {int userId = 1}) => MainScreenConfig(
      userRole: role,
      userId: userId,
      enablePageAnimation: false,
      customNavItems: [
        BottomNavItem(
          label: 'Home',
          labelKey: 'nav_home',
          icon: Icons.home,
          routeName: 'home',
          showCallFab: true,
          screen: const Scaffold(body: Text('Home Shell')),
        ),
        BottomNavItem(
          label: 'Messages',
          icon: Icons.message,
          routeName: 'messages',
          screen: const Scaffold(body: Text('Messages Shell')),
        ),
        BottomNavItem(
          label: 'Settings',
          icon: Icons.settings,
          routeName: 'settings',
          screen: const Scaffold(body: Text('Settings Shell')),
        ),
      ],
    );

Widget _wrap({
  required UserProvider provider,
  MainScreenConfig? config,
  bool withConfig = true,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            MainScreen(config: withConfig ? (config ?? _config('PATIENT')) : null),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Page')),
      ),
      GoRoute(
        path: '/somewhere',
        builder: (_, __) => const Scaffold(body: Text('Somewhere Page')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
      (call) async => null,
    );
  });

  group('quick video-call picker', () {
    testWidgets('patient sees enabled caregivers and a self-call is refused',
        (tester) async {
      _bigView(tester);
      (_Backend()
            ..caregiversByPatient = {
              1: [
                {
                  'caregiverUserId': 7,
                  'caregiverName': 'Zed Carer',
                  'patientVideoCallsEnabled': true,
                },
                {
                  'caregiverUserId': 1,
                  'caregiverName': '',
                  'patientVideoCallsEnabled': 'true',
                },
                {
                  'caregiverUserId': 9,
                  'caregiverName': 'Disabled',
                  'patientVideoCallsEnabled': false,
                },
                {'caregiverUserId': 'x'},
              ],
            })
          .install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);

      await tester.tap(find.byTooltip('Start video call'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await _settle(tester);

      expect(find.text('Zed Carer'), findsOneWidget);
      expect(find.text('Disabled'), findsNothing);
      // Caregiver with no name falls back to "<role> <id>"; it is the user's
      // own id, so the call is refused.
      final selfTile = find.textContaining(' 1').first;
      await tester.tap(selfTile);
      await _settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('patient with no callable caregivers sees the empty message',
        (tester) async {
      _bigView(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      await tester.tap(find.byTooltip('Start video call'));
      await _settle(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      expect(find.text(t.mainscreen_noCaregiverAvailable), findsOneWidget);
    });

    testWidgets('caregiver sees assigned patients and their care team',
        (tester) async {
      _bigView(tester);
      (_Backend()
            ..caregiverPatients = [
              {
                'link': {'patientUserId': 20},
                'patient': {
                  'firstName': 'Ana',
                  'lastName': 'Diaz',
                  'email': 'ana@example.test',
                  'phone': '555-0100',
                },
              },
              {
                'link': {
                  'patientUserId': 21,
                  'patientName': 'Linked Name',
                  'patientEmail': 'ln@example.test',
                },
                'patient': {},
              },
              // Duplicate and invalid rows are skipped.
              {
                'link': {'patientUserId': 20},
              },
              {'link': {}},
              'garbage',
            ]
            ..caregiversByPatient = {
              20: [
                {
                  'caregiverUserId': 30,
                  'caregiverName': 'Bea Team',
                  'caregiverEmail': ''
                },
                {'caregiverUserId': 2}, // the current caregiver
              ],
              21: [
                {
                  'caregiverUserId': 30,
                  'caregiverName': 'Bea Team',
                  'caregiverEmail': 'bea@example.test',
                },
                {'caregiverUserId': 31},
              ],
            })
          .install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(
          mockUser: MockUser(
              id: 2, role: 'CAREGIVER', patientId: null, caregiverId: 5),
        ),
        config: _config('CAREGIVER', userId: 2),
      ));
      await _settle(tester);
      await tester.tap(find.byTooltip('Start video call'));
      await _settle(tester);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.text('Linked Name'), findsOneWidget);
      expect(find.text('Bea Team'), findsOneWidget);
      expect(find.textContaining('Ana Diaz, Linked Name'), findsOneWidget);

      // Bea is reachable through a linked patient, so the call opens.
      await tester.tap(find.text('Bea Team'));
      await _settle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(HybridVideoCallWidget), findsOneWidget);
    });

    testWidgets('caregiver picker handles failing and non-list responses',
        (tester) async {
      _bigView(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      final b = _Backend()..caregiverPatientsStatus = 500;
      b.install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(
          mockUser: MockUser(
              id: 2, role: 'CAREGIVER', patientId: null, caregiverId: 5),
        ),
        config: _config('CAREGIVER', userId: 2),
      ));
      await _settle(tester);
      await tester.tap(find.byTooltip('Start video call'));
      await _settle(tester);
      expect(find.text(t.mainscreen_noAssignedPat), findsOneWidget);
      Navigator.of(tester.element(find.text(t.mainscreen_noAssignedPat)))
          .pop();
      await _settle(tester);

      b
        ..caregiverPatientsStatus = 200
        ..caregiverPatients = {'not': 'a list'};
      await tester.tap(find.byTooltip('Start video call'));
      await _settle(tester);
      expect(find.text(t.mainscreen_noAssignedPat), findsOneWidget);
    });

    testWidgets('caregiver without caregiverId gets no targets',
        (tester) async {
      _bigView(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(
          mockUser: MockUser(id: 2, role: 'CAREGIVER', patientId: null),
        ),
        config: _config('CAREGIVER', userId: 2),
      ));
      await _settle(tester);
      await tester.tap(find.byTooltip('Start video call'));
      await _settle(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      expect(find.text(t.mainscreen_noAssignedPat), findsOneWidget);
    });

    testWidgets('call FAB is hidden for unsupported roles', (tester) async {
      _bigView(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'ADMIN')),
        config: _config('ADMIN'),
      ));
      await _settle(tester);
      expect(find.byTooltip('Start video call'), findsNothing);
    });
  });

  group('unread messages badge', () {
    testWidgets('shows the unread count, clears it on the messages tab',
        (tester) async {
      _bigView(tester);
      (_Backend()
            ..inbox = [
              {'hasUnread': true},
              {'hasUnread': true},
              {'hasUnread': false},
            ])
          .install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      expect(find.text('2'), findsOneWidget);

      // App resume refreshes the badge; detach clears auth data.
      final state = tester.state(find.byType(MainScreen)) as dynamic;
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle(tester);
      state.didChangeAppLifecycleState(AppLifecycleState.detached);
      await _settle(tester);

      await tester.tap(find.text('Messages'));
      await _settle(tester);
      expect(find.text('Messages Shell'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      // Periodic polling refresh after 60 seconds.
      await tester.pump(const Duration(seconds: 61));
      await _settle(tester);
    });

    testWidgets('caps the badge at 99+', (tester) async {
      _bigView(tester);
      (_Backend()
            ..inbox = [
              for (var i = 0; i < 120; i++) {'hasUnread': true}
            ])
          .install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('narrow screens use the wrapping nav bar with the badge',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      (_Backend()
            ..inbox = [
              {'hasUnread': true},
            ])
          .install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await _settle(tester);
      expect(find.text('Settings Shell'), findsOneWidget);
    });

    testWidgets('inbox failure keeps the badge hidden', (tester) async {
      _bigView(tester);
      (_Backend()..inboxStatus = 500).install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      expect(find.text('Home Shell'), findsOneWidget);
    });
  });

  group('voice command flyout callbacks', () {
    Future<VoiceCommandAI> openFlyout(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Voice commands'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return tester.widget<VoiceCommandAI>(find.byType(VoiceCommandAI));
    }

    testWidgets('close and dashboard navigation dismiss the flyout',
        (tester) async {
      _bigView(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);

      var flyout = await openFlyout(tester);
      flyout.onCloseRequested!();
      await _settle(tester);
      expect(find.byType(VoiceCommandAI), findsNothing);

      await tester.tap(find.text('Settings'));
      await _settle(tester);
      flyout = await openFlyout(tester);
      flyout.onNavigateRequested!('/dashboard');
      await _settle(tester);
      expect(find.byType(VoiceCommandAI), findsNothing);
      expect(find.text('Home Shell'), findsOneWidget);
    });

    testWidgets('other destinations route through GoRouter', (tester) async {
      _bigView(tester);
      _Backend().install();
      await tester.pumpWidget(_wrap(
        provider: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
      ));
      await _settle(tester);
      final flyout = await openFlyout(tester);
      flyout.onNavigateRequested!('/somewhere');
      await _settle(tester);
      expect(find.text('Somewhere Page'), findsOneWidget);
    });
  });

  group('session handling without a config', () {
    testWidgets('a role change rebuilds the navigation', (tester) async {
      _bigView(tester);
      _Backend().install();
      final provider = MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
      await tester.pumpWidget(_wrap(provider: provider, withConfig: false));
      await _settle(tester);
      provider.setMockRole('CAREGIVER', caregiverId: 3);
      await _settle(tester);
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });

  group('navigation extension', () {
    testWidgets('navigateToMainScreen variants replace the route',
        (tester) async {
      _bigView(tester);
      _Backend().install();
      final provider = MockUserProvider(mockUser: MockUser(role: 'PATIENT'));
      Future<void> run(void Function(BuildContext) go) async {
        final router = GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (context, __) => Scaffold(
              body: TextButton(
                onPressed: () => go(context),
                child: const Text('go'),
              ),
            ),
          ),
        ]);
        await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ));
        await tester.tap(find.text('go'));
        await _settle(tester);
        expect(find.byType(MainScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      }

      await run((c) => c.navigateToMainScreen(config: _config('PATIENT')));
      await run((c) =>
          c.navigateToMainScreenWithConfig(_config('PATIENT'), tabIndex: 1));
    });
  });
}
