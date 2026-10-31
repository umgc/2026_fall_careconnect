// Tests for BillingQuoteService (lib/services/billing_quote_service.dart) and
// GooglePlacesService (lib/services/google_places_service.dart). Both use
// package:http top-level calls, intercepted with http.runWithClient.

import 'dart:convert';

import 'package:care_connect_app/services/billing_quote_service.dart';
import 'package:care_connect_app/services/google_places_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('BillingQuoteService', () {
    final service = BillingQuoteService(backendBase: 'https://api.example.test');

    test('returns a parsed quote with display helpers', () async {
      Map<String, dynamic>? sent;
      final quote = await http.runWithClient(
        () => service.getQuote(
          tierId: 2,
          userId: 5,
          state: 'MD',
          postalCode: '20742',
          city: 'College Park',
        ),
        () => MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({
                'tierId': 2,
                'tierName': 'Plus',
                'subtotalCents': 1999,
                'taxCents': 120,
                'totalCents': 2119,
                'currency': 'USD',
                'taxRate': 0.06,
                'taxJurisdiction': 'MD',
              }),
              200);
        }),
      );
      expect(sent?['state'], 'MD');
      expect(quote.tierName, 'Plus');
      expect(quote.subtotalDisplay, r'$19.99');
      expect(quote.taxDisplay, r'$1.20');
      expect(quote.totalDisplay, r'$21.19');
      expect(quote.taxPercentageDisplay, '6.00%');
      expect(BillingQuote.fromJson(const {}).taxJurisdiction, 'UNKNOWN');
    });

    test('401 and other failures throw', () async {
      await expectLater(
        http.runWithClient(() => service.getQuote(tierId: 1),
            () => MockClient((_) async => http.Response('no', 401))),
        throwsA(predicate((e) => '$e'.contains('requires authentication'))),
      );
      await expectLater(
        http.runWithClient(() => service.getQuote(tierId: 1),
            () => MockClient((_) async => http.Response('boom', 500))),
        throwsA(predicate((e) => '$e'.contains('500'))),
      );
    });
  });

  group('GooglePlacesService', () {
    final service = GooglePlacesService(backendBase: 'https://api.example.test');

    test('suggestions parse predictions and handle edge responses', () async {
      expect(await service.getSuggestions('  '), isEmpty);

      final list = await http.runWithClient(
        () => service.getSuggestions('123 Main'),
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'OK',
              'predictions': [
                {
                  'main_text': '123 Main St',
                  'secondary_text': 'Town, MD',
                  'place_id': 'p1',
                  'description': '123 Main St, Town, MD',
                },
              ],
            }),
            200)),
      );
      expect(list.single.placeId, 'p1');
      expect(list.single.toString(), '123 Main St, Town, MD');

      expect(
        await http.runWithClient(
          () => service.getSuggestions('x'),
          () => MockClient((_) async =>
              http.Response(jsonEncode({'status': 'NO_API_KEY'}), 200)),
        ),
        isEmpty,
      );
      expect(
        await http.runWithClient(() => service.getSuggestions('x'),
            () => MockClient((_) async => http.Response('', 500))),
        isEmpty,
      );
      expect(
        await http.runWithClient(() => service.getSuggestions('x'),
            () => MockClient((_) async => throw Exception('down'))),
        isEmpty,
      );

      final s = AddressSuggestion.fromJson({
        'main_text': 'a',
        'secondary_text': 'b',
        'place_id': 'c',
        'description': 'd',
      });
      expect(s.mainText, 'a');
    });

    test('place details parse components or fall back to the string',
        () async {
      final parsed = await service.getPlaceDetails('1 Elm St, Town, md 20742');
      expect(parsed.state, 'MD');
      expect(parsed.zip, '20742');

      final details = await http.runWithClient(
        () => service.getPlaceDetails('place-1'),
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'result': {
                'address_components': [
                  {
                    'types': ['street_number'],
                    'long_name': '10',
                    'short_name': '10'
                  },
                  {
                    'types': ['route'],
                    'long_name': 'Oak Ave',
                    'short_name': 'Oak'
                  },
                  {
                    'types': ['locality'],
                    'long_name': 'Laurel',
                    'short_name': 'Laurel'
                  },
                  {
                    'types': ['administrative_area_level_1'],
                    'long_name': 'Maryland',
                    'short_name': 'md'
                  },
                  {
                    'types': ['postal_code'],
                    'long_name': '20707',
                    'short_name': '20707'
                  },
                ],
                'geometry': {
                  'location': {'lat': 39.1, 'lng': -76.8}
                },
              }
            }),
            200)),
      );
      expect(details.street, '10 Oak Ave');
      expect(details.city, 'Laurel');
      expect(details.state, 'MD');
      expect(details.latitude, 39.1);

      final noResult = await http.runWithClient(
        () => service.getPlaceDetails('place-2'),
        () => MockClient((_) async => http.Response('{}', 200)),
      );
      expect(noResult.street, 'place-2');
      final thrown = await http.runWithClient(
        () => service.getPlaceDetails('place-3'),
        () => MockClient((_) async => throw Exception('down')),
      );
      expect(thrown.street, 'place-3');

      final short = ParsedAddress.parseFromString('Only street');
      expect(short.city, '');
    });
  });
}
