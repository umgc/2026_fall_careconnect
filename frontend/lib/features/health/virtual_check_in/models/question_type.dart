/// Must mirror backend enum: TEXT, YES_NO, TRUE_FALSE, NUMBER
enum BackendQuestionType {
  text, // TEXT
  yesNo, // YES_NO
  trueFalse, // TRUE_FALSE
  number; // NUMBER

  /// Convert backend wire value -> enum
  static BackendQuestionType fromWire(String? value) {
    final s = (value ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    switch (s) {
      case 'TEXT':
        return BackendQuestionType.text;
      case 'YES_NO':
        return BackendQuestionType.yesNo;
      case 'TRUE_FALSE':
        return BackendQuestionType.trueFalse;
      case 'NUMBER':
      case 'NUMERIC': // tolerate alias if it ever appears
        return BackendQuestionType.number;
      default:
        // Fallback so UI doesn’t crash; you can log this if you want
        return BackendQuestionType.text;
    }
  }

  /// Convert enum -> backend wire value
  String toWire() {
    switch (this) {
      case BackendQuestionType.text:
        return 'TEXT';
      case BackendQuestionType.yesNo:
        return 'YES_NO';
      case BackendQuestionType.trueFalse:
        return 'TRUE_FALSE';
      case BackendQuestionType.number:
        return 'NUMBER';
    }
  }
}
