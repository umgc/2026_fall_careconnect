// Interaction tests for FileUploadWidget on a non-web platform: choosing a
// category, the per-category instructions, picking a photo through the
// image_picker channel, and the QuickUploadButtons dialog.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../mock_user_provider.dart';

const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late List<MethodCall> pickerCalls;
  late String? pickedPath;

  setUp(() {
    pickerCalls = <MethodCall>[];
    pickedPath = '/photos/me.jpg';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async {
      pickerCalls.add(call);
      return pickedPath;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, null);
  });

  testWidgets('selecting a file before a category asks for one',
      (tester) async {
    await _pump(tester, const FileUploadWidget());
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(pickerCalls, isEmpty);
  });

  testWidgets('every category can be chosen and shows its instructions',
      (tester) async {
    await _pump(tester, const FileUploadWidget());
    final t = lookupAppLocalizations(const Locale('en'));
    expect(find.text(t.fileuploadwidget_selectCatFirst), findsOneWidget);
    final perCategory = <FileCategory, String>{
      FileCategory.profilePicture: t.fileuploadwidget_tapSelectPFP,
      FileCategory.prescription: t.fileuploadwidget_tapSelectPrescrip,
      FileCategory.medicalReport: t.fileuploadwidget_tapSelectMedDoc,
      FileCategory.labResult: t.fileuploadwidget_tapSelectMedDoc,
      FileCategory.insuranceDoc: t.fileuploadwidget_tapSelectInsurance,
    };
    for (final category in FileCategory.values) {
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(category.icon).last);
      await tester.pumpAndSettle();
      expect(
        find.text(perCategory[category] ?? t.fileuploadwidget_tapSelectFile),
        findsOneWidget,
        reason: category.name,
      );
    }
  });

  testWidgets('a picked profile photo is shown with a description field',
      (tester) async {
    await _pump(
      tester,
      const FileUploadWidget(
        defaultCategory: FileCategory.profilePicture,
        allowedCategories: [FileCategory.profilePicture],
        customTitle: 'Upload photo',
      ),
    );
    expect(find.text('Upload photo'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
    await tester.pumpAndSettle();
    await tester
        .tap(find.textContaining(FileCategory.profilePicture.icon).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    await tester.pump();
    expect(pickerCalls.single.method, 'pickImage');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.textContaining('/photos/me.jpg'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('cancelling the photo picker keeps the empty selector',
      (tester) async {
    pickedPath = null;
    await _pump(tester, const FileUploadWidget(showCategorySelector: false));
    expect(find.byType(DropdownButtonFormField<FileCategory>), findsNothing);
    await _pump(
      tester,
      const FileUploadWidget(allowedCategories: [FileCategory.prescription]),
    );
    await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(FileCategory.prescription.icon).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('quick upload buttons open an upload dialog', (tester) async {
    await _pump(tester, const QuickUploadButtons(patientId: 3));
    await tester.tap(find.byIcon(Icons.science));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(FileUploadWidget), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
