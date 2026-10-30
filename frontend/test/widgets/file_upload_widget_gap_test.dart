// Gap test for FileUploadWidget (lib/widgets/file_upload_widget.dart): its
// category dropdown is a form field, so validating the surrounding form
// without a category must show the "no category selected" message, and picking
// a category clears it.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/widgets/file_upload_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../mock_user_provider.dart';

void main() {
  testWidgets('validating without a category asks for one', (tester) async {
    final t = lookupAppLocalizations(const Locale('en'));
    final formKey = GlobalKey<FormState>();
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(key: formKey, child: const FileUploadWidget()),
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(t.manualentrywidget_noCateSelected), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(FileCategory.labResult.icon).last);
    await tester.pumpAndSettle();
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text(t.manualentrywidget_noCateSelected), findsNothing);
  });
}
