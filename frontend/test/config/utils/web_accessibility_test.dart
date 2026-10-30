import 'package:care_connect_app/config/utils/web_accessibility.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('turns the semantics tree on for the web', () {
    final handle = enableWebAccessibility(isWeb: true);

    expect(handle, isNotNull);
    expect(SemanticsBinding.instance.semanticsEnabled, isTrue);

    handle!.dispose();
  });

  test('does nothing on other platforms', () {
    expect(enableWebAccessibility(isWeb: false), isNull);
  });
}
