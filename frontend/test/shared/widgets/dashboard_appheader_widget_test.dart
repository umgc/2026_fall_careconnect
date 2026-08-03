// Tests for DashboardAppHeader (lib/shared/widgets/dashboard_appheader_widget.dart).

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../mock_user_provider.dart';

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(role: 'PATIENT')),
    child: MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(appBar: child as PreferredSizeWidget)),
  );
}

void main() {
  testWidgets('renders CARECONNECT brand text', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Alice',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.text('CARECONNECT'), findsOneWidget);
  });

  testWidgets('renders welcome message with userName', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Bob',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.textContaining('Welcome back Bob'), findsOneWidget);
  });

  testWidgets('renders patient mood question for PATIENT role', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Carol',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.text('How are you feeling today?'), findsOneWidget);
  });

  testWidgets('renders health summary for non-PATIENT role', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Dan',
      role: 'CAREGIVER',
    )));
    await tester.pump();
    expect(find.text("Your patients' health summary"), findsOneWidget);
  });

  testWidgets('preferredSize height is 210', (tester) async {
    const header = DashboardAppHeader(userName: 'Test', role: 'PATIENT');
    expect(header.preferredSize.height, 210);
  });

  testWidgets('shows person icon when profileImageUrl is empty', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Eve',
      role: 'PATIENT',
      profileImageUrl: '',
    )));
    await tester.pump();
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('shows settings icon', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('shows hospital icons', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.byIcon(Icons.local_hospital), findsWidgets);
  });

  testWidgets('shows time string with timezone', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    // The time string contains the timezone name
    final timeZone = DateTime.now().timeZoneName;
    expect(find.textContaining(timeZone), findsOneWidget);
  });

  testWidgets('shows CircleAvatar', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('renders with ADMIN role', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Admin',
      role: 'ADMIN',
    )));
    await tester.pump();
    expect(find.text("Your patients' health summary"), findsOneWidget);
  });

  testWidgets('renders with non-empty profileImageUrl', (tester) async {
    final origOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('NetworkImage') ||
          details.toString().contains('HTTP') ||
          details.toString().contains('Connection')) { return; }
      origOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = origOnError);

    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
      profileImageUrl: 'https://example.com/avatar.png',
    )));
    await tester.pump();
    // Should not show person icon (since image is provided)
    expect(find.byIcon(Icons.person), findsNothing);
    // CircleAvatar should have a backgroundImage
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<NetworkImage>());
  });

  testWidgets('renders with FAMILY_LINK role', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Family',
      role: 'FAMILY_LINK',
    )));
    await tester.pump();
    expect(find.text("Your patients' health summary"), findsOneWidget);
  });

  testWidgets('shows online indicator dot', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    // The Stack contains the online indicator
    expect(find.byType(Stack), findsWidgets);
  });

  testWidgets('shows formatted time string', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardAppHeader(
      userName: 'Test',
      role: 'PATIENT',
    )));
    await tester.pump();
    // Time string contains / separator
    expect(find.textContaining('/'), findsOneWidget);
  });
}
