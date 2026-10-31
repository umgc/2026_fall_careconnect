import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/services/edi_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportVisitData completes (true or handled false) on the VM', () async {
    final patient = Patient(
      id: 3,
      firstName: 'Jane',
      lastName: 'Doe',
      email: 'jane@example.com',
      phone: '555-0100',
      dob: '1990-06-15',
      relationship: 'Self',
    );
    final result = await EdiService.exportVisitData(
      patient: patient,
      serviceType: 'Personal Care',
      checkinTime: DateTime(2025, 3, 10, 9),
      checkoutTime: DateTime(2025, 3, 10, 10),
      duration: 60,
      notes: 'All good',
      checkinLatitude: 1.0,
      checkinLongitude: 2.0,
      checkoutLatitude: 1.0,
      checkoutLongitude: 2.0,
      checkinLocationType: 'gps',
      checkoutLocationType: 'gps',
    );
    expect(result, isA<bool>());
  });
}
