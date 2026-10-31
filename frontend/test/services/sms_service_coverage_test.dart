import 'package:care_connect_app/services/sms_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('sendSMS returns true when the SMS app can be launched', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final ok = await SMSService.sendMedicationReminder(
      phoneNumber: '(555) 123-4567',
      patientName: 'Pat',
      medicationName: 'Aspirin',
      dosage: '81mg',
    );
    expect(ok, isTrue);
    expect(calls, contains('canLaunch'));
  });

  test('sendSMS returns false when launcher throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'fail');
    });
    final ok = await SMSService.sendSMS(phoneNumber: '555', message: 'hi');
    expect(ok, isFalse);
  });
}
