import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';

CheckInQuestionType mapTypeToUi(BackendQuestionType t) {
  switch (t) {
    case BackendQuestionType.number:
      return CheckInQuestionType.numerical;
    case BackendQuestionType.yesNo:
    case BackendQuestionType.trueFalse:
      return CheckInQuestionType.yesNo;
    case BackendQuestionType.text:
      return CheckInQuestionType.textInput;
  }
}

VirtualCheckInQuestion toUiQuestion(BackendQuestionDto dto) {
  return VirtualCheckInQuestion(
    id: dto.id.toString(),
    type: mapTypeToUi(dto.type),
    required: dto.required,
    text: dto.prompt,
    formKey: dto.formKey,
    formVersion: dto.formVersion,
    sectionKey: dto.sectionKey,
    fieldKey: dto.fieldKey,
    scoreWeight: dto.scoreWeight,
  );
}
