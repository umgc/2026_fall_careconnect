import 'dart:convert';

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ApiService.debugResetHttpClient);

  test('sendShareCard posts only receiverId and normalized kind', () async {
    http.Request? sentRequest;
    ApiService.debugSetHttpClient(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'message': {'id': 55},
            'receiverCanView': false,
          }),
          200,
        );
      }),
    );

    final response = await ApiService.sendShareCard(
      receiverId: 300,
      kind: 'medicare',
    );

    expect(response.statusCode, 200);
    expect(sentRequest!.method, 'POST');
    expect(sentRequest!.url.path, endsWith('/messages/share'));
    expect(jsonDecode(sentRequest!.body), {
      'receiverId': 300,
      'kind': 'MEDICARE',
    });
  });
}
