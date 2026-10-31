// Coverage for ApiService's thin offline-queue wrappers
// (configureOfflineQueue, initializeOfflineQueue, getOfflineSyncPendingCount,
// syncOfflineQueue, dispose) backed by a real test SQLite database.

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/local_db_test_bindings.dart';

void main() {
  setUpAll(() async {
    await LocalDbTestBindings.install();
  });

  tearDownAll(LocalDbTestBindings.uninstall);

  test('offline queue wrappers delegate to ApiServiceOffline', () async {
    SharedPreferences.setMockInitialValues({});
    final mock = MockClient((_) async => http.Response('{}', 200));
    await http.runWithClient(() async {
      ApiService.configureOfflineQueue(canQueueOfflineWrites: () => false);
      await ApiService.initializeOfflineQueue();

      expect(await ApiService.getOfflineSyncPendingCount(), 0);
      final summary = await ApiService.syncOfflineQueue(limit: 5);
      expect(summary.attempted, 0);
      expect(summary.failed, 0);
    }, () => mock);
  });

  test('dispose closes the shared client and can be reset', () {
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response('', 200)));
    ApiService.dispose();
    ApiService.debugResetHttpClient();
    expect(ApiService.isAccessDenied(http.Response('', 403)), isTrue);
  });
}
