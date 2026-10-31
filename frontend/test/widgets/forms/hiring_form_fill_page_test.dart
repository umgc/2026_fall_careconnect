// Widget tests for HiringFormFillPage: every field control, conditional
// visibility, the required-field check, the confirmation summary and each
// submission outcome (created, validation errors, other failure).

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/models/hiring_form_models.dart';
import 'package:care_connect_app/widgets/forms/hiring_form_fill_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _definition = FormDefinition(
  formType: 'W4',
  title: 'Employee Withholding',
  version: '2026',
  fileCategory: 'TAX',
  sections: [
    FormSectionDef(
      id: 'personal',
      title: 'Personal details',
      order: 1,
      completedBy: 'EMPLOYEE',
      fields: [
        FormFieldDef(
          id: 'name',
          label: 'Full name',
          fieldType: FormFieldType.text,
          required: true,
          order: 1,
          helpText: 'As shown on your card',
        ),
        FormFieldDef(
          id: 'notes',
          label: 'Notes',
          fieldType: FormFieldType.textarea,
          required: false,
          order: 2,
        ),
        FormFieldDef(
          id: 'salary',
          label: 'Salary',
          fieldType: FormFieldType.currency,
          required: false,
          order: 3,
        ),
        FormFieldDef(
          id: 'email',
          label: 'Email',
          fieldType: FormFieldType.email,
          required: false,
          order: 4,
        ),
        FormFieldDef(
          id: 'phone',
          label: 'Phone',
          fieldType: FormFieldType.phone,
          required: false,
          order: 5,
        ),
        FormFieldDef(
          id: 'ssn',
          label: 'SSN',
          fieldType: FormFieldType.ssn,
          required: false,
          order: 6,
          sensitive: true,
        ),
        FormFieldDef(
          id: 'citizen',
          label: 'US citizen',
          fieldType: FormFieldType.boolean,
          required: true,
          order: 7,
          helpText: 'Tick if yes',
        ),
        FormFieldDef(
          id: 'agree',
          label: 'Agree to terms',
          fieldType: FormFieldType.checkbox,
          required: false,
          order: 8,
        ),
        FormFieldDef(
          id: 'status',
          label: 'Filing status',
          fieldType: FormFieldType.select,
          required: true,
          order: 9,
          options: [
            FieldOption(value: 'single', label: 'Single'),
            FieldOption(value: 'married', label: 'Married'),
          ],
        ),
        FormFieldDef(
          id: 'start',
          label: 'Start date',
          fieldType: FormFieldType.date,
          required: false,
          order: 10,
        ),
        FormFieldDef(
          id: 'id_doc',
          label: 'ID document',
          fieldType: FormFieldType.fileRef,
          required: false,
          order: 11,
        ),
        FormFieldDef(
          id: 'skills',
          label: 'Skills',
          fieldType: FormFieldType.multiselect,
          required: false,
          order: 12,
          options: [
            FieldOption(value: 'cpr', label: 'CPR'),
            FieldOption(value: 'lift', label: 'Lifting'),
          ],
        ),
        FormFieldDef(
          id: 'spouse',
          label: 'Spouse name',
          fieldType: FormFieldType.text,
          required: true,
          order: 13,
          visibleWhen: VisibilityCondition(
            fieldId: 'status',
            equalsValue: 'married',
          ),
        ),
      ],
    ),
    FormSectionDef(
      id: 'hidden',
      title: 'Hidden section',
      order: 2,
      fields: [
        FormFieldDef(
          id: 'never',
          label: 'Never shown',
          fieldType: FormFieldType.text,
          required: true,
          order: 1,
          visibleWhen: VisibilityCondition(fieldId: 'status', equalsValue: 'x'),
        ),
      ],
    ),
  ],
);

Future<void> _open(
  WidgetTester tester, {
  FormDefinition definition = _definition,
  List<bool?>? results,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => HiringFormFillPage(
                    definition: definition,
                    patientId: 7,
                  ),
                ),
              );
              results?.add(result);
            },
            child: const Text('open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
}

Future<void> _fillRequired(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Full name *'),
    'Pat Example',
  );
  await tester.tap(find.text('US citizen *'));
  await tester.pump();
  await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Filing status *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Married').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Spouse name *'),
    'Sam Example',
  );
}

Future<void> _submitAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  late List<http.Request> requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = <http.Request>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read' &&
          (call.arguments as Map)['key'] == 'jwt_token') {
        return 'jwt';
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  MockClient respond(
    int status,
    Map<String, dynamic> body, {
    Future<void>? hold,
  }) =>
      MockClient((request) async {
        if (!request.url.path.endsWith('forms/submissions')) {
          return http.Response('{}', 200);
        }
        requests.add(request);
        if (hold != null) await hold;
        return http.Response(jsonEncode(body), status);
      });

  testWidgets('renders every field control and hides conditional ones',
      (tester) async {
    await _open(tester);

    expect(find.text('Personal details'), findsOneWidget);
    expect(find.textContaining('employee'), findsOneWidget);
    expect(find.text('Hidden section'), findsNothing);
    expect(find.text('Spouse name *'), findsNothing);
    expect(find.text('Tick if yes'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
  });

  testWidgets('submitting with required fields empty lists them',
      (tester) async {
    await _open(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(
      find.textContaining('Please complete required fields: Full name'),
      findsOneWidget,
    );
    expect(find.textContaining('Filing status'), findsWidgets);
  });

  testWidgets('cancelling the confirmation submits nothing', (tester) async {
    await http.runWithClient(() async {
      await _open(tester);
      await _fillRequired(tester);
      expect(find.text('Spouse name *'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Pat Example'), findsWidgets);
      expect(find.text('Married'), findsWidgets);
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
    }, () => respond(201, {}));
  });

  testWidgets('a confirmed submission is saved and closes the form',
      (tester) async {
    final results = <bool?>[];
    await http.runWithClient(() async {
      await _open(tester, results: results);
      await _fillRequired(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Notes'), 'Some notes');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Salary'), '  ');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'pat@example.com');
      await tester.tap(find.text('Agree to terms'));
      await tester.pump();
      await tester.tap(find.text('Agree to terms'));
      await tester.pump();

      await tester.tap(find.text('CPR'));
      await tester.pump();
      await tester.tap(find.text('Lifting'));
      await tester.pump();
      await tester.tap(find.text('Lifting'));
      await tester.pump();

      await tester.tap(find.text('Select date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Select date'), findsNothing);

      await _submitAndConfirm(tester);
      expect(results, [true]);
    },
        () => respond(201, {
              'message': 'Created',
              'data': {'id': 9}
            }));

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final values = body['fieldValues'] as Map<String, dynamic>;
    expect(values['personal.name'], 'Pat Example');
    expect(values['personal.citizen'], true);
    expect(values['personal.skills'], ['cpr']);
    expect(values.containsKey('personal.salary'), isFalse);
    expect(body['patientId'], 7);
  });

  testWidgets('date picker can be dismissed without choosing', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Select date').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Select date'), findsOneWidget);
  });

  testWidgets('server validation errors are listed in a dialog',
      (tester) async {
    await http.runWithClient(() async {
      await _open(tester);
      await _fillRequired(tester);
      await _submitAndConfirm(tester);
      expect(find.text('Bad form'), findsOneWidget);
      expect(find.text('SSN is invalid'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Bad form'), findsNothing);
    },
        () => respond(422, {
              'error': 'Bad form',
              'details': ['SSN is invalid'],
            }));
  });

  testWidgets('other submission failures show the server error',
      (tester) async {
    final hold = Completer<void>();
    await http.runWithClient(() async {
      await _open(tester);
      await _fillRequired(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('…'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text('Server down'), findsOneWidget);
      expect(find.byType(HiringFormFillPage), findsOneWidget);
    }, () => respond(500, {'error': 'Server down'}, hold: hold.future));
  });

  testWidgets('a form with nothing entered says so in the summary',
      (tester) async {
    const optionalOnly = FormDefinition(
      formType: 'NOTE',
      title: 'Optional note',
      version: '1',
      fileCategory: 'MISC',
      sections: [
        FormSectionDef(
          id: 's',
          title: 'Only section',
          order: 1,
          fields: [
            FormFieldDef(
              id: 'memo',
              label: 'Memo',
              fieldType: FormFieldType.text,
              required: false,
              order: 1,
            ),
          ],
        ),
      ],
    );
    await _open(tester, definition: optionalOnly);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Memo'), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
  });
}
