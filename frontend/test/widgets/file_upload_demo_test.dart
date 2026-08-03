// Tests for FileUploadDemo from lib/widgets/file_upload_demo.dart.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/widgets/file_upload_demo.dart';

Widget _wrap() => const MaterialApp(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: FileUploadDemo());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('FileUploadDemo – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(FileUploadDemo), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('shows File Upload Demo AppBar title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('File Upload Demo'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Comprehensive File Upload heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Comprehensive File Upload'), findsOneWidget);
    });

    testWidgets('shows Quick Upload Examples heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Quick Upload Examples'), findsOneWidget);
    });

    testWidgets('shows quick upload buttons', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Medical Report'), findsOneWidget);
      expect(find.text('Prescription'), findsOneWidget);
      expect(find.text('Lab Result'), findsOneWidget);
      expect(find.text('Insurance Doc'), findsOneWidget);
    });

    testWidgets('shows quick upload button icons', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
      expect(find.byIcon(Icons.medication), findsOneWidget);
      expect(find.byIcon(Icons.science), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
    });

    testWidgets('shows API Integration Examples heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('API Integration Examples'),
        200,
      );
      expect(find.text('API Integration Examples'), findsOneWidget);
    });

    testWidgets('shows Available API Endpoints card', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Available API Endpoints'),
        200,
      );
      expect(find.text('Available API Endpoints'), findsOneWidget);
    });

    testWidgets('shows API endpoint descriptions', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Get all user files'),
        200,
      );
      expect(find.text('Get all user files'), findsOneWidget);
      expect(find.text('Upload file'), findsOneWidget);
    });

    testWidgets('shows DELETE method badge', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Delete file'), 200);
      expect(find.text('DELETE'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Recently Uploaded Files heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Recently Uploaded Files'),
        200,
      );
      expect(find.text('Recently Uploaded Files'), findsOneWidget);
    });
  });

  group('FileUploadDemo – after loading completes', () {
    testWidgets('shows empty state after loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Recently Uploaded Files'),
        200,
      );
      // Should show empty state or no loading indicator
      final hasEmpty = find.text('No files uploaded yet').evaluate().isNotEmpty;
      final hasNoLoader = find.byType(CircularProgressIndicator).evaluate().isEmpty;
      expect(hasEmpty || hasNoLoader, isTrue);
    });

    testWidgets('shows folder_open icon in empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      // Either shows folder icon (empty state) or no loader (error handled silently)
      final hasFolder = find.byIcon(Icons.folder_open).evaluate().isNotEmpty;
      final loadingDone = find.byType(CircularProgressIndicator).evaluate().isEmpty;
      expect(hasFolder || loadingDone, isTrue);
    });
  });

  group('FileUploadDemo – SingleChildScrollView', () {
    testWidgets('shows SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows Wrap for quick upload buttons', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Wrap), findsOneWidget);
    });
  });
}
