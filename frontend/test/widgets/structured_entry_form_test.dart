import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/structured_entry_service.dart';
import 'package:care_connect_app/widgets/structured_entry_form.dart';

void main() {
  final capturedRequests = <http.Request>[];
  http.Response Function(http.Request request)? responder;

  setUp(() {
    capturedRequests.clear();
    responder = null;
    // Stub out the network and auth layers.
    StructuredEntryService.client = MockClient((request) async {
      capturedRequests.add(request);
      if (responder != null) return responder!(request);
      return http.Response(
        json.encode({
          'data': {
            'id': 5,
            'fileId': 20,
            'documentType': 'REFERENCE',
            'patientId': 7,
            'fields': {'referenceName': 'Jane Doe'},
            'originalFilename': 'ref-letter.pdf',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    StructuredEntryService.authHeadersProvider =
        () async => {'Content-Type': 'application/json'};
  });

  tearDown(() {
    StructuredEntryService.client = http.Client();
  });

  /// Pumps a host page with a button that opens the structured-entry dialog,
  /// mirroring how the file management / patient files pages launch it.
  Future<void> openDialog(
    WidgetTester tester, {
    String fileCategory = 'REFERENCE',
    int? patientId,
    int? employeeUserId,
    StructuredEntryDTO? existingEntry,
    void Function(bool?)? onClosed,
  }) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await StructuredEntryFormDialog.show(
                  context,
                  fileId: 20,
                  fileName: 'ref-letter.pdf',
                  fileCategory: fileCategory,
                  patientId: patientId,
                  employeeUserId: employeeUserId,
                  existingEntry: existingEntry,
                );
                onClosed?.call(result);
              },
              child: const Text('open structured entry'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open structured entry'));
    await tester.pumpAndSettle();
  }

  Future<void> fillField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final field = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  // ElevatedButton.icon builds a private ElevatedButton subclass, so exact
  // type matching (widgetWithText) misses it — match by subtype instead.
  ElevatedButton saveButton(WidgetTester tester, String label) =>
      tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );

  group('UI form creation', () {
    testWidgets('user can open the structured-entry form from a file action',
        (tester) async {
      await openDialog(tester, patientId: 7);

      expect(find.text('New Structured Entry'), findsOneWidget);
      expect(find.text('Save Entry'), findsOneWidget);
      // Field set for the file's document type is rendered.
      expect(
        find.widgetWithText(TextFormField, 'Reference name *'),
        findsOneWidget,
      );
    });

    testWidgets('original uploaded file stays visibly linked to the record',
        (tester) async {
      await openDialog(tester, patientId: 7);

      expect(find.text('ref-letter.pdf'), findsOneWidget);
      expect(
        find.text('Original file stays linked as supporting evidence'),
        findsOneWidget,
      );
    });
  });

  group('UI edit mode', () {
    testWidgets('existing structured record loads into editable fields',
        (tester) async {
      final existing = StructuredEntryDTO(
        id: 5,
        fileId: 20,
        documentType: 'REFERENCE',
        patientId: 7,
        fields: {'referenceName': 'Jane Doe', 'relationship': 'Former employer'},
      );

      await openDialog(tester, existingEntry: existing);

      expect(find.text('Edit Structured Entry'), findsOneWidget);
      expect(find.text('Update Entry'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Former employer'), findsOneWidget);
    });
  });

  group('Document type', () {
    testWidgets('form fields change based on the selected document type',
        (tester) async {
      await openDialog(tester, fileCategory: 'CERTIFICATION', patientId: 7);

      expect(
        find.widgetWithText(TextFormField, 'Certification name *'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Reference name *'),
        findsNothing,
      );

      // Switch document type: Certification -> Reference.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference').last);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextFormField, 'Reference name *'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Certification name *'),
        findsNothing,
      );
    });
  });

  group('Context requirement', () {
    testWidgets('save is blocked when patient/employee context is missing',
        (tester) async {
      await openDialog(tester); // no patientId, no employeeUserId

      expect(
        find.textContaining('No patient or employee is associated'),
        findsOneWidget,
      );
      expect(saveButton(tester, 'Save Entry').onPressed, isNull,
          reason: 'Save must be disabled');
      expect(capturedRequests, isEmpty);
    });

    testWidgets('patient context from the patient files page is shown',
        (tester) async {
      await openDialog(tester, patientId: 7);

      expect(find.text('Patient record #7'), findsOneWidget);
    });

    testWidgets('employee context is shown for caregiver-owned documents',
        (tester) async {
      await openDialog(tester, employeeUserId: 3);

      expect(find.text('Employee record #3'), findsOneWidget);
    });
  });

  group('Required fields and validation messages', () {
    testWidgets(
        'save is blocked and errors display beside incomplete required fields',
        (tester) async {
      await openDialog(tester, patientId: 7);

      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();

      // Clear inline errors for each missing required field.
      expect(find.text('Reference name is required'), findsOneWidget);
      expect(find.text('Relationship is required'), findsOneWidget);
      // Nothing was submitted and the dialog stayed open.
      expect(capturedRequests, isEmpty);
      expect(find.text('New Structured Entry'), findsOneWidget);
    });

    testWidgets('optional fields do not block saving', (tester) async {
      await openDialog(tester, patientId: 7);

      await fillField(tester, 'Reference name *', 'Jane Doe');
      await fillField(tester, 'Relationship *', 'Former employer');
      // Phone / email / notes left empty on purpose.
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();

      expect(capturedRequests, hasLength(1));
    });
  });

  group('Successful save', () {
    testWidgets('valid entry submits the correct payload to the backend',
        (tester) async {
      bool? dialogResult;
      await openDialog(
        tester,
        patientId: 7,
        onClosed: (result) => dialogResult = result,
      );

      await fillField(tester, 'Reference name *', 'Jane Doe');
      await fillField(tester, 'Relationship *', 'Former employer');
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();

      expect(capturedRequests, hasLength(1));
      final request = capturedRequests.single;
      expect(request.method, 'POST');
      // File linkage: the entry is created against the uploaded file's ID.
      expect(request.url.path, endsWith('/v1/api/files/20/structured-entry'));

      final body = json.decode(request.body) as Map<String, dynamic>;
      expect(body['documentType'], 'REFERENCE');
      expect(body['patientId'], 7);
      expect(body['fields']['referenceName'], 'Jane Doe');
      expect(body['fields']['relationship'], 'Former employer');

      // Dialog closed reporting success and confirmed via snackbar.
      expect(dialogResult, isTrue);
      expect(find.text('New Structured Entry'), findsNothing);
      expect(find.text('Structured entry saved'), findsOneWidget);
    });
  });

  group('Update flow', () {
    testWidgets('editing an existing entry sends an update, not a create',
        (tester) async {
      final existing = StructuredEntryDTO(
        id: 5,
        fileId: 20,
        documentType: 'REFERENCE',
        patientId: 7,
        fields: {'referenceName': 'Jane Doe', 'relationship': 'Employer'},
      );
      await openDialog(tester, existingEntry: existing);

      await fillField(tester, 'Relationship *', 'Former employer');
      await tester.tap(find.text('Update Entry'));
      await tester.pumpAndSettle();

      expect(capturedRequests, hasLength(1));
      final request = capturedRequests.single;
      expect(request.method, 'PUT');
      expect(
        request.url.path,
        endsWith('/v1/api/files/structured-entries/5'),
      );
      final body = json.decode(request.body) as Map<String, dynamic>;
      expect(body['fields']['relationship'], 'Former employer');
      expect(find.text('Structured entry updated'), findsOneWidget);
    });
  });

  group('Error handling', () {
    testWidgets('backend failure shows the error and keeps user input',
        (tester) async {
      responder = (request) => http.Response(
            json.encode({
              'error': 'Missing required fields for REFERENCE: relationship',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );

      await openDialog(tester, patientId: 7);
      await fillField(tester, 'Reference name *', 'Jane Doe');
      await fillField(tester, 'Relationship *', 'Employer');
      await tester.tap(find.text('Save Entry'));
      await tester.pumpAndSettle();

      // Error surfaced to the user...
      expect(
        find.textContaining('Missing required fields for REFERENCE'),
        findsOneWidget,
      );
      // ...the dialog stays open and the typed values are preserved.
      expect(find.text('New Structured Entry'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Employer'), findsOneWidget);
      // Save is re-enabled for a retry.
      expect(saveButton(tester, 'Save Entry').onPressed, isNotNull);
    });
  });
}
