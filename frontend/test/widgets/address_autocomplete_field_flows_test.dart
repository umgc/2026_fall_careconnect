// AddressAutocompleteField with the address backend served by a MockClient:
// typing shows suggestions, choosing one fills the field and reports the
// parsed address.

import 'dart:convert';

import 'package:care_connect_app/services/google_places_service.dart';
import 'package:care_connect_app/widgets/address_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('selecting a suggestion fills and parses the address',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final selected = <ParsedAddress>[];
    final changes = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/suggestions')) {
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'predictions': [
              {
                'main_text': '1 Main St',
                'secondary_text': 'Springfield, IL',
                'place_id': 'place-1',
                'description': '1 Main St, Springfield, IL 62701',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'result': {
            'address_components': [
              {
                'types': ['street_number'],
                'long_name': '1',
              },
              {
                'types': ['route'],
                'long_name': 'Main St',
              },
              {
                'types': ['locality'],
                'long_name': 'Springfield',
              },
              {
                'types': ['administrative_area_level_1'],
                'short_name': 'il',
              },
              {
                'types': ['postal_code'],
                'long_name': '62701',
              },
            ],
            'geometry': {
              'location': {'lat': 39.8, 'lng': -89.6},
            },
          },
        }),
        200,
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressAutocompleteField(
              controller: controller,
              label: 'Address',
              isRequired: true,
              onAddressSelected: selected.add,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Ma');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1 Main');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1 Main St'), findsOneWidget);

      await tester.tap(find.text('1 Main St'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.text, '1 Main St, Springfield, IL 62701');

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
    }, () => client);

    expect(selected, isNotEmpty);
    expect(selected.first.city, 'Springfield');
    expect(changes, isNotEmpty);
  });
}
