// Tests for ScheduleApiService.
// (lib/features/shift_scheduling/services/schedule_api_service.dart)
//
// Error-path and constructor tests only. Successful HTTP paths require
// injecting ApiClient.instance which is a separate singleton.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/shift_scheduling/services/schedule_api_service.dart';
import 'package:care_connect_app/services/api_client.dart';

/// Dio adapter that fails immediately — never touches the network.
class _ImmediateFailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'mocked connection failure',
      message: 'mocked connection failure',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduleApiService', () {
    late ScheduleApiService service;
    late HttpClientAdapter originalAdapter;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient.instance;
      originalAdapter = api.debugHttpClientAdapter;
      api.debugSetTimeouts();
      api.debugSetHttpClientAdapter(_ImmediateFailAdapter());
      service = ScheduleApiService();
    });

    tearDown(() {
      ApiClient.instance.debugSetHttpClientAdapter(originalAdapter);
      ApiClient.instance.debugSetTimeouts(
        connect: const Duration(seconds: 20),
        receive: const Duration(seconds: 30),
        send: const Duration(seconds: 20),
      );
    });

    test('can be instantiated', () {
      expect(service, isA<ScheduleApiService>());
    });

    test('getDaySchedule returns empty list on error', () async {
      final visits = await service.getDaySchedule(1, DateTime(2026, 3, 17));
      expect(visits, isA<List>());
      expect(visits, isEmpty);
    });

    test('getMonthSchedule returns empty list on error', () async {
      final visits = await service.getMonthSchedule(1, 2026, 3);
      expect(visits, isA<List>());
      expect(visits, isEmpty);
    });

    test('getWeekSchedule returns empty list on error', () async {
      final visits = await service.getWeekSchedule(1, DateTime(2026, 3, 16));
      expect(visits, isA<List>());
      expect(visits, isEmpty);
    });

    test('checkConflicts returns null on error', () async {
      final conflict = await service.checkConflicts(1, {
        'patientId': 10,
        'scheduledDate': '2026-03-17',
      });
      expect(conflict, isNull);
    });

    test('getAuditHistory returns empty list on error', () async {
      final audits = await service.getAuditHistory(42);
      expect(audits, isA<List>());
      expect(audits, isEmpty);
    });
  });
}
