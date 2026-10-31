// Coverage tests for FileUploadWidget (lib/widgets/file_upload_widget.dart):
// the category selector's validator messages.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('category validator requires a selection', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: FileUploadWidget())),
    ));
    await tester.pump();
    final t = lookupAppLocalizations(const Locale('en'));
    final dropdown = tester.widget<DropdownButtonFormField<FileCategory>>(
      find.byType(DropdownButtonFormField<FileCategory>),
    );
    expect(dropdown.validator!(null), t.manualentrywidget_noCateSelected);
    expect(dropdown.validator!(FileCategory.labResult), isNull);
    expect(find.text(t.manualentrywidget_selectCat), findsOneWidget);
    expect(find.text(t.fileuploadwidget_selectCatFirst), findsOneWidget);
  });
}
