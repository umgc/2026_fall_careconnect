// Tests for SelectPackagePage — subscription plan selection screen.
// initState calls _fetchSubscriptionPlans() which makes a real HTTP call.
// tester.runAsync allows the connection-refused failure to propagate,
// after which the error view is shown with the error message and Retry button.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/payments/presentation/pages/select_package_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

Widget _wrap() {
  // CommonDrawer inside SelectPackagePage needs UserProvider.
  final provider = UserProvider()
    ..setUser(UserSession(
      id: 1,
      email: 'caregiver@test.com',
      role: 'caregiver',
      token: 'token',
      caregiverId: 1,
    ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: SelectPackagePage(),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Mock connectivity_plus channel to avoid MissingPluginException
    // when UserProvider._initConnectivity is triggered in runAsync tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => ['wifi'],
    );
  });

  group('SelectPackagePage – initial loading state', () {
    testWidgets('renders Scaffold', (tester) async {
      // Verifies the page builds without crashing.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // pumpWidget renders the first frame with isLoading = true.
      // Do NOT call pump() again — real HTTP may complete between awaits
      // and update isLoading to false before we can check for the spinner.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('SelectPackagePage – error state (API fails)', () {
    testWidgets('shows error text after API fails', (tester) async {
      // tester.runAsync allows real I/O to fail (server returns non-200 or
      // flutter_secure_storage throws). The catch/else block sets errorMessage.
      await tester.pumpWidget(_wrap());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      // errorMessage is non-null; _buildErrorView renders the error text.
      expect(find.textContaining('load'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Retry button in error state', (tester) async {
      // _buildErrorView has an ElevatedButton labeled "Retry".
      await tester.pumpWidget(_wrap());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows error_outline icon in error view', (tester) async {
      // _buildErrorView includes Icons.error_outline as a large icon.
      await tester.pumpWidget(_wrap());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows refresh icon button in AppBar', (tester) async {
      // The AppBar always contains a refresh IconButton regardless of state.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping Retry shows error state again', (tester) async {
      // Tapping Retry calls _fetchSubscriptionPlans() again. The HTTP call
      // returns 400 immediately in tests, so isLoading returns to false before
      // the next pump; the error view reappears with the Retry button.
      await tester.pumpWidget(_wrap());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
