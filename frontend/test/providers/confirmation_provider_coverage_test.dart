import 'dart:convert';

import 'package:care_connect_app/providers/confirmation_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _item(int id, String status) =>
    {'id': id, 'status': status, 'title': 'Item $id'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  MockClient okClient() => MockClient((req) async {
        if (req.url.path.endsWith('/pending')) {
          return http.Response(
            jsonEncode([_item(1, 'PENDING'), _item(2, 'PENDING')]),
            200,
          );
        }
        return http.Response(jsonEncode({'id': 1}), 200);
      });

  test('fetchFromBackend loads items, confirm/dismiss update state', () async {
    final provider = ConfirmationProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await http.runWithClient(() async {
      await provider.fetchFromBackend(sourceType: 'AI_CHAT');
      expect(provider.items, hasLength(2));
      expect(provider.isLoading, isFalse);

      expect(await provider.confirmItem(1, note: 'ok'), isTrue);
      expect(provider.getItemById(1)!['status'], 'CONFIRMED');

      expect(await provider.dismissItem(2, note: 'no'), isTrue);
      expect(provider.getItemById(2)!['status'], 'DISMISSED');
    }, okClient);

    expect(notifications, greaterThan(3));

    final reloaded = ConfirmationProvider();
    await reloaded.loadFromCache();
    expect(reloaded.items, hasLength(2));

    await reloaded.clear();
    expect(reloaded.items, isEmpty);
  });

  test('backend failures leave state unchanged', () async {
    final provider = ConfirmationProvider();
    provider.setItemsForTest([_item(5, 'PENDING')]);
    await http.runWithClient(() async {
      await provider.fetchFromBackend();
      expect(provider.items, hasLength(1));
      expect(await provider.confirmItem(5), isFalse);
      expect(await provider.dismissItem(5), isFalse);
    }, () => MockClient((_) async => http.Response('nope', 500)));
    expect(provider.getItemById(5)!['status'], 'PENDING');
  });
}
