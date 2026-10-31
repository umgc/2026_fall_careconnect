import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/widgets/address_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
      'shows loading spinner, reopens suggestions on tap, selects by '
      'description when placeId is empty, and shows API-key status',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final gate = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/suggestions')) {
        await gate.future;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'predictions': [
              {
                'main_text': '9 Elm St',
                'secondary_text': 'Dover, DE',
                'place_id': '',
                'description': '9 Elm St, Dover, DE 19901',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'result': {}}), 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressAutocompleteField(
              controller: controller,
              label: 'Address',
              googlePlacesApiKey: 'test-key',
            ),
          ),
        ),
      );
      expect(find.text('Google Places API active ✓'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '9 Elm');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('9 Elm St'), findsOneWidget);

      // Tapping the field again while suggestions exist re-shows them.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

      await tester.tap(find.text('9 Elm St'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.text, '9 Elm St, Dover, DE 19901');
    }, () => client);
  });
}
