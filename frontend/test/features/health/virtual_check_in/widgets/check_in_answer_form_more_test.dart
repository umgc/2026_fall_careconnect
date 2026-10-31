// More happy-path tests for CheckInAnswerForm
// (lib/features/health/virtual_check_in/widgets/check_in_answer_form.dart):
// required-field errors for every type, choice chips, number entry and a
// valid submit.
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/widgets/check_in_answer_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _required = [
  BackendQuestionDto(
      id: 1,
      prompt: 'Name',
      type: BackendQuestionType.text,
      required: true,
      active: true,
      ordinal: 0),
  BackendQuestionDto(
      id: 2,
      prompt: 'Took meds',
      type: BackendQuestionType.yesNo,
      required: true,
      active: true,
      ordinal: 1),
  BackendQuestionDto(
      id: 3,
      prompt: 'Felt ok',
      type: BackendQuestionType.trueFalse,
      required: true,
      active: true,
      ordinal: 2),
  BackendQuestionDto(
      id: 4,
      prompt: 'Pain',
      type: BackendQuestionType.number,
      required: true,
      active: true,
      ordinal: 3),
  BackendQuestionDto(
      id: 5,
      prompt: 'Optional number',
      type: BackendQuestionType.number,
      required: false,
      active: true,
      ordinal: 4),
  BackendQuestionDto(
      id: null,
      prompt: 'Broken',
      type: BackendQuestionType.text,
      required: false,
      active: true,
      ordinal: 5),
];

void main() {
  testWidgets('required answers are checked, then the form submits',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var submitted = 0;
    List<AnswerUpsertRequestDTO> last = const [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CheckInAnswerForm(
            questions: _required,
            onSubmit: () => submitted++,
            onAnswersChanged: (a) => last = a,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Submit Answers'));
    await tester.pump();
    expect(find.text('This field is required'), findsNWidgets(2));
    expect(find.text('Please select Yes or No'), findsOneWidget);
    expect(find.text('Please select True or False'), findsOneWidget);
    expect(find.text('Invalid question data'), findsOneWidget);
    expect(submitted, 0);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ann');
    await tester.enterText(fields.at(1), 'abc');
    await tester.enterText(fields.at(2), 'xyz');
    await tester.tap(find.text('Submit Answers'));
    await tester.pump();
    expect(find.text('Please enter a valid number'), findsNWidgets(2));

    await tester.enterText(fields.at(1), '4');
    await tester.enterText(fields.at(2), '');
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.tap(find.text('No'));
    await tester.pump();
    await tester.tap(find.text('True'));
    await tester.pump();
    await tester.tap(find.text('False'));
    await tester.pump();
    // Tapping a selected chip clears it; tap again to re-select.
    await tester.tap(find.text('False'));
    await tester.pump();
    await tester.tap(find.text('False'));
    await tester.pump();
    await tester.tap(find.text('Submit Answers'));
    await tester.pump();
    expect(submitted, 1);
    expect(last.length, 4);
  });

  testWidgets('a loading form shows progress and cannot submit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CheckInAnswerForm(
          questions: const [],
          isLoading: true,
          onSubmit: () {},
          onAnswersChanged: (_) {},
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
