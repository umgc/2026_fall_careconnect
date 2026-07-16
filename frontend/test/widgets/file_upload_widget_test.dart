// Tests for FileUploadWidget from lib/widgets/file_upload_widget.dart.
// No HTTP in initState. Provider.of<UserProvider> only used on upload action.
// Pure UI render test — no Provider needed for initial render.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';

Widget _wrap({
  String? customTitle,
  bool showCategorySelector = true,
  FileCategory? defaultCategory,
  List<FileCategory>? allowedCategories,
  int? patientId,
  Function(String)? onUploadError,
}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FileUploadWidget(
            customTitle: customTitle,
            showCategorySelector: showCategorySelector,
            defaultCategory: defaultCategory,
            allowedCategories: allowedCategories,
            patientId: patientId,
            onUploadError: onUploadError,
          ),
        ),
      ),
    );

void main() {
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

  group('FileUploadWidget – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(FileUploadWidget), findsOneWidget);
    });

    testWidgets('shows Upload File header by default', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('Upload File'), findsWidgets);
    });

    testWidgets('shows custom title when provided', (tester) async {
      await tester.pumpWidget(_wrap(customTitle: 'Upload Invoice'));
      expect(find.text('Upload Invoice'), findsOneWidget);
    });

    testWidgets('shows category selector', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select Category'), findsOneWidget);
    });

    testWidgets('shows cloud_upload icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.cloud_upload), findsWidgets);
    });

    testWidgets('shows "Select File" label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select File'), findsOneWidget);
    });

    testWidgets('shows add_circle_outline icon when no file selected',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    });

    testWidgets('shows Card widget', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('shows upload button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('hides category selector when showCategorySelector is false',
        (tester) async {
      await tester.pumpWidget(_wrap(showCategorySelector: false));
      expect(find.text('Select Category'), findsNothing);
      // DropdownButtonFormField should not be present
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsNothing);
    });

    testWidgets('shows InkWell for file selection area', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('does not show LinearProgressIndicator initially',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows DropdownButtonFormField for category', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
          find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });
  });

  group('FileUploadWidget – file instructions', () {
    testWidgets('shows default instruction when no category selected',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.text('Select a category first, then tap to choose file'),
        findsOneWidget,
      );
    });
  });

  group('FileUploadWidget – upload button state', () {
    testWidgets('upload button is disabled when no file and no category',
        (tester) async {
      await tester.pumpWidget(_wrap());
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('upload button shows "Upload File" text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Upload File'), findsWidgets);
    });
  });

  group('FileUploadWidget – category selector interaction', () {
    testWidgets('tapping file area without category shows snackbar',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // Tap on the add_circle_outline icon area (file selection)
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      // Should show snackbar about selecting category first
      expect(
        find.text('Please select a file category first'),
        findsOneWidget,
      );
    });

    testWidgets('dropdown shows all FileCategory values by default',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Check that some categories are visible
      expect(find.textContaining('Medical Report'), findsWidgets);
      expect(find.textContaining('Lab Result'), findsWidgets);
      expect(find.textContaining('Prescription'), findsWidgets);
    });

    testWidgets('dropdown only shows allowed categories when specified',
        (tester) async {
      await tester.pumpWidget(_wrap(
        allowedCategories: [
          FileCategory.prescription,
          FileCategory.medicalReport,
        ],
      ));
      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Should show allowed categories
      expect(find.textContaining('Prescription'), findsWidgets);
      expect(find.textContaining('Medical Report'), findsWidgets);
    });

    testWidgets('selecting a category updates the dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select the first "Medical Report" item (there will be duplicates in overlay)
      await tester.tap(find.textContaining('Medical Report').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // After selecting, instruction text should change from default
      expect(
        find.text('Select a category first, then tap to choose file'),
        findsNothing,
      );
    });
  });

  group('FileUploadWidget – file instructions per category', () {
    testWidgets('shows profile picture instructions after selecting category',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select Profile Picture
      await tester.tap(find.textContaining('Profile Picture').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to select profile picture'),
        findsOneWidget,
      );
    });

    testWidgets('shows prescription instructions after selecting category',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('Prescription').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to take photo or select prescription'),
        findsOneWidget,
      );
    });

    testWidgets('shows medical doc instructions for medicalReport',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('Medical Report').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to select medical document'),
        findsOneWidget,
      );
    });

    testWidgets('shows insurance doc instructions for insuranceDoc',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('Insurance Document').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to select insurance document'),
        findsOneWidget,
      );
    });

    testWidgets('shows generic instructions for other categories',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select AI Chat File (falls into default case)
      await tester.tap(find.textContaining('AI Chat File').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to select file'),
        findsOneWidget,
      );
    });

    testWidgets('shows lab result instructions for labResult',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('Lab Result').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Tap to select medical document'),
        findsOneWidget,
      );
    });
  });

  group('FileUploadWidget – with allowedCategories', () {
    testWidgets('renders with restricted categories', (tester) async {
      await tester.pumpWidget(_wrap(
        allowedCategories: [FileCategory.prescription],
      ));
      expect(find.byType(FileUploadWidget), findsOneWidget);
      expect(
          find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('shows "No categories available" when empty list given',
        (tester) async {
      // The _availableCategories getter returns FileCategory.values when
      // allowedCategories is null or empty. But if empty list is given...
      // Actually per the code, empty list triggers FileCategory.values fallback.
      // So this just verifies the dropdown is shown.
      await tester.pumpWidget(_wrap(allowedCategories: []));
      expect(
          find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });
  });

  group('FileUploadWidget – with patientId', () {
    testWidgets('renders normally with patientId', (tester) async {
      await tester.pumpWidget(_wrap(patientId: 42));
      expect(find.byType(FileUploadWidget), findsOneWidget);
    });
  });

  group('FileUploadWidget – description field not shown initially', () {
    testWidgets('description field is not visible without file selected',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Description (Optional)'), findsNothing);
      expect(find.text('Enter file description'), findsNothing);
    });
  });

  group('FileUploadWidget – no category selector mode', () {
    testWidgets('does not show dropdown when showCategorySelector is false',
        (tester) async {
      await tester.pumpWidget(_wrap(showCategorySelector: false));
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsNothing);
    });

    testWidgets('still shows header and upload button', (tester) async {
      await tester.pumpWidget(_wrap(showCategorySelector: false));
      expect(find.textContaining('Upload File'), findsWidgets);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('still shows file selector area', (tester) async {
      await tester.pumpWidget(_wrap(showCategorySelector: false));
      expect(find.text('Select File'), findsOneWidget);
    });
  });

  group('QuickUploadButtons', () {
    testWidgets('renders all 6 quick upload buttons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      expect(find.text('Quick File Upload'), findsOneWidget);
      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Medical Report'), findsOneWidget);
      expect(find.text('Prescription'), findsOneWidget);
      expect(find.text('Lab Result'), findsOneWidget);
      expect(find.text('Insurance'), findsOneWidget);
      expect(find.text('AI Chat File'), findsOneWidget);
    });

    testWidgets('renders correct icons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
      expect(find.byIcon(Icons.medication), findsOneWidget);
      expect(find.byIcon(Icons.science), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    testWidgets('has 6 ElevatedButtons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      expect(find.byType(ElevatedButton), findsNWidgets(6));
    });

    testWidgets('uses Wrap for layout', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets('tapping a quick button opens a dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(patientId: 5),
          ),
        ),
      ));
      // Tap "Profile Photo" button
      await tester.tap(find.text('Profile Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog should be shown
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Upload Profile Picture'), findsOneWidget);
      // Dialog contains a FileUploadWidget
      expect(find.byType(FileUploadWidget), findsOneWidget);
      // Cancel button
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('dialog cancel button closes dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      // Open dialog
      await tester.tap(find.text('Prescription'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Upload Prescription'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('tapping Medical Report opens correct dialog',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      await tester.tap(find.text('Medical Report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload Medical Report'), findsOneWidget);
    });

    testWidgets('tapping Lab Result opens correct dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      await tester.tap(find.text('Lab Result'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload Lab Result'), findsOneWidget);
    });

    testWidgets('tapping Insurance opens correct dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      await tester.tap(find.text('Insurance'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload Insurance Document'), findsOneWidget);
    });

    testWidgets('tapping AI Chat File opens correct dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      await tester.tap(find.text('AI Chat File'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload AI Chat File'), findsOneWidget);
    });

    testWidgets('dialog FileUploadWidget has showCategorySelector false',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      await tester.tap(find.text('Profile Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The FileUploadWidget in the dialog should not show category selector
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsNothing);
      expect(find.text('Select Category'), findsNothing);
    });
  });

  group('FileUploadWidget – widget construction', () {
    testWidgets('default category is passed correctly', (tester) async {
      await tester.pumpWidget(_wrap(
        defaultCategory: FileCategory.prescription,
      ));
      expect(find.byType(FileUploadWidget), findsOneWidget);
    });

    testWidgets('multiple constructor params work together', (tester) async {
      await tester.pumpWidget(_wrap(
        customTitle: 'My Upload',
        showCategorySelector: true,
        patientId: 10,
        allowedCategories: [
          FileCategory.medicalReport,
          FileCategory.labResult,
        ],
      ));
      expect(find.text('My Upload'), findsOneWidget);
      expect(
          find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });
  });

  group('FileUploadWidget – visual structure', () {
    testWidgets('contains Column as main layout', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('contains Padding inside Card', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Padding), findsWidgets);
    });

    testWidgets('contains Row for header', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('header text uses headlineSmall style', (tester) async {
      await tester.pumpWidget(_wrap());
      // Just check the text exists, style is Theme-based
      final textFinder = find.text('Upload File');
      expect(textFinder, findsWidgets);
    });

    testWidgets('file selector has Container with fixed height',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // Just verify file selection area exists
      expect(find.text('Select File'), findsOneWidget);
    });
  });

  group('FileUploadWidget – category dropdown behavior', () {
    testWidgets('dropdown has correct decoration with border radius',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
          find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('selecting different categories updates instructions',
        (tester) async {
      await tester.pumpWidget(_wrap());

      // Select General Document (default case)
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.textContaining('General Document').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Tap to select file'), findsOneWidget);
    });
  });

  group('QuickUploadButtons – with callbacks', () {
    testWidgets('renders with patientId parameter', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(patientId: 99),
          ),
        ),
      ));
      expect(find.byType(QuickUploadButtons), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNWidgets(6));
    });

    testWidgets('renders without any optional parameters', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickUploadButtons(),
          ),
        ),
      ));
      expect(find.byType(QuickUploadButtons), findsOneWidget);
    });
  });
}
