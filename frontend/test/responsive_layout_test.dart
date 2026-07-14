import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/caregiver_dashboard.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('Responsive Layout Tests', () {
    Widget buildTestWidget() {
      final mockUser = UserSession(
        id: 1,
        email: 'test@example.com',
        role: 'caregiver',
        token: 'mock_token',
        caregiverId: 1,
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const CaregiverDashboard(),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login')),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) =>
                const Scaffold(body: Text('Analytics')),
          ),
          GoRoute(
            path: '/add-patient',
            builder: (context, state) =>
                const Scaffold(body: Text('Add Patient')),
          ),
          GoRoute(
            path: '/evv/select-patient',
            builder: (context, state) => const Scaffold(body: Text('EVV')),
          ),
          GoRoute(
            path: '/patient/:id',
            builder: (context, state) => const Scaffold(body: Text('Patient')),
          ),
        ],
      );

      return ChangeNotifierProvider(
        create: (_) => UserProvider()..setUser(mockUser),
        child: MaterialApp.router(
          routerConfig: router,
        ),
      );
    }

    testWidgets('CaregiverDashboard adapts to different screen sizes',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Use pump with duration instead of pumpAndSettle to avoid timeout
      await tester.pump(const Duration(seconds: 2));

      // Check if the dashboard renders without errors
      expect(find.byType(CaregiverDashboard), findsOneWidget);
    });

    testWidgets(
        'Team C smoke: dashboard remains usable at responsive breakpoints',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 2));

      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final size in const [
        Size(300, 600),
        Size(600, 800),
        Size(1200, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump(const Duration(seconds: 1));

        expect(
          MediaQuery.sizeOf(
            tester.element(find.byType(CaregiverDashboard)),
          ),
          size,
          reason: 'App surface should match the $size smoke breakpoint',
        );
        expect(find.byType(CaregiverDashboard), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'Dashboard should render at $size without layout errors');
      }
    });
  });
}
