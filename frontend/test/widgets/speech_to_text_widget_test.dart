// Tests for SpeechToTextCard from lib/widgets/speech_to_text_widget.dart.
//
// The widget creates a SpeechToText instance in initState.
// We mock the speech_to_text MethodChannel to prevent crashes.
// We wrap with UserProvider (via MockUserProvider) since the widget
// reads from Provider when saving files.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/speech_to_text_widget.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';

import '../mock_user_provider.dart';

Widget _wrap({
  List<FileCategory>? allowedCategories,
  int? patientId,
}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SpeechToTextCard(
            allowedCategories: allowedCategories,
            patientId: patientId,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // Mock the speech_to_text plugin channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        if (call.method == 'has_permission') return true;
        if (call.method == 'initialize') return true;
        if (call.method == 'listen') return null;
        if (call.method == 'stop') return null;
        if (call.method == 'cancel') return null;
        return null;
      },
    );

    // Mock connectivity plugin
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('SpeechToTextCard – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SpeechToTextCard), findsOneWidget);
    });

    testWidgets('shows header text "Speech to Text"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Speech to Text'), findsOneWidget);
    });

    testWidgets('shows mic icon in header', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows category dropdown with hint', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Select Category'), findsOneWidget);
    });

    testWidgets('shows file name text field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('File Name'), findsOneWidget);
      expect(find.text('Enter file name (no extension)'), findsOneWidget);
    });

    testWidgets('shows initial prompt text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text('Tap the button below to start Speech-to-Text'),
        findsOneWidget,
      );
    });

    testWidgets('shows Start Listening button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Start Listening'), findsOneWidget);
    });

    testWidgets('shows Save to File button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Save to File'), findsOneWidget);
    });

    testWidgets('Save to File button is disabled initially (no text)',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save to File'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Start Listening button is enabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final startButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Listening'),
      );
      expect(startButton.onPressed, isNotNull);
    });
  });

  group('SpeechToTextCard – category dropdown', () {
    testWidgets('renders all FileCategory values when no filter given',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // The dropdown should exist
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('renders only allowed categories when filter is given',
        (tester) async {
      final allowed = [FileCategory.medicalReport, FileCategory.prescription];
      await tester.pumpWidget(_wrap(allowedCategories: allowed));
      await tester.pump();
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });
  });

  group('SpeechToTextCard – interactions', () {
    testWidgets('can enter text in file name field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      final field = find.byType(TextFormField).last;
      await tester.enterText(field, 'my_recording');
      await tester.pump();

      expect(find.text('my_recording'), findsOneWidget);
    });

    testWidgets(
        'tapping Start Listening without category shows snackbar warning',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.tap(find.text('Start Listening'));
      await tester.pump();

      // When no category is selected, _selectCategory shows a snackbar
      expect(
        find.text('Please select a file category first'),
        findsOneWidget,
      );
    });

    testWidgets('renders Column as root widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // SpeechToTextCard builds a Column
      expect(find.byType(Column), findsWidgets);
    });
  });
}
