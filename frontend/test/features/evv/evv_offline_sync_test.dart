import 'package:care_connect_app/l10n/app_localizations.dart';
// Tests for EvvOfflineSyncPage
// (lib/features/evv/presentation/pages/evv_offline_sync.dart).
//
// _isLoading starts true; _loadSyncQueue() API call has try/catch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_offline_sync.dart';

Widget _wrap() => MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: const EvvOfflineSyncPage());

void main() {
  group('EvvOfflineSyncPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(EvvOfflineSyncPage), findsOneWidget);
    });

    testWidgets('shows "Offline Sync" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Offline Sync'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });
  });
}
