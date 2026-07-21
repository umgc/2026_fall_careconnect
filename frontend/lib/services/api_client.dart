import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/env_constant.dart';
import '../features/telemetry/telemetry_error_handler.dart';
import 'auth_token_manager.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  final dynamic data;
  final String? code;

  ApiException({this.status, required this.message, this.data, this.code});

  @override
  String toString() =>
      'ApiException(status=$status, code=$code, message=$message)';
}

class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: getBackendBaseUrl(),
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
        followRedirects: false,
        validateStatus: (code) => code != null && code >= 100 && code < 600,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Attach Bearer token if present
          final token = await AuthTokenManager.getJwtToken();
          if (token != null && (options.headers['Authorization'] == null)) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Basic logging in debug
          if (kDebugMode) {
            debugPrint('[API] ${options.method} ${options.uri}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          // Update last activity on any successful 2xx
          if (response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300) {
            await AuthTokenManager.updateLastActivity();
            handler.next(response);
            return;
          }

          // Convert non 2xx into ApiException
          handler.reject(_asDioError(response));
        },
        onError: (err, handler) async {
          final req = err.requestOptions;

          final status = err.response?.statusCode;
          final alreadyRetried = req.extra['__ret'] == true;

          if (status == 401 && !alreadyRetried) {
            try {
              final refreshed = await AuthService.forceRefreshToken();
              if (refreshed != null) {
                final newToken = await AuthTokenManager.getJwtToken();
                if (newToken != null) {
                  final clone = await _retryWithToken(req, newToken);
                  handler.resolve(clone);
                  return;
                }
              }
            } catch (_) {
              // fall through to error
            }
          }

          _recordDioErrorTelemetry(err);

          // Normalize to a DioException that wraps ApiException for consistency
          handler.reject(_normalizeDioError(err));
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;

  /// Replace Dio's HTTP adapter so tests fail fast without real network I/O.
  @visibleForTesting
  void debugSetHttpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  /// Current Dio HTTP adapter (tests only — for restore after overrides).
  @visibleForTesting
  HttpClientAdapter get debugHttpClientAdapter => _dio.httpClientAdapter;

  /// Apply very short Dio timeouts (tests only).
  @visibleForTesting
  void debugSetTimeouts({
    Duration connect = const Duration(milliseconds: 50),
    Duration receive = const Duration(milliseconds: 50),
    Duration send = const Duration(milliseconds: 50),
  }) {
    _dio.options.connectTimeout = connect;
    _dio.options.receiveTimeout = receive;
    _dio.options.sendTimeout = send;
  }

  // --------------- Public generic methods ---------------

  Future<T> getJson<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic json)? parser,
  }) async {
    final resp = await _dio.get(
      path,
      queryParameters: query,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
    return _parse<T>(resp, parser);
  }

  Future<T> postJson<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic json)? parser,
  }) async {
    final resp = await _dio.post(
      path,
      data: body,
      queryParameters: query,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
    return _parse<T>(resp, parser);
  }

  Future<T> putJson<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic json)? parser,
  }) async {
    final resp = await _dio.put(
      path,
      data: body,
      queryParameters: query,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
    return _parse<T>(resp, parser);
  }

  Future<T> patchJson<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic json)? parser,
  }) async {
    final resp = await _dio.patch(
      path,
      data: body,
      queryParameters: query,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
    return _parse<T>(resp, parser);
  }

  Future<T> deleteJson<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic json)? parser,
  }) async {
    final resp = await _dio.delete(
      path,
      data: body,
      queryParameters: query,
      options: Options(headers: headers),
      cancelToken: cancelToken,
    );
    return _parse<T>(resp, parser);
  }

  /// Multipart upload. `files` is a map from field name to File. You can pass
  /// strings and other fields in `fields`.
  Future<T> uploadMultipart<T>(
    String path, {
    required Map<String, File> files,
    Map<String, String>? fields,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    T Function(dynamic json)? parser,
  }) async {
    final formMap = <String, dynamic>{};
    if (fields != null) {
      formMap.addAll(fields);
    }
    for (final entry in files.entries) {
      final name = entry.key;
      final file = entry.value;
      formMap[name] = await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
      );
    }

    final formData = FormData.fromMap(formMap);

    final resp = await _dio.post(
      path,
      data: formData,
      queryParameters: query,
      options: Options(
        headers: {
          ...?headers,
          // Let Dio set proper content type for multipart
          'Content-Type': 'multipart/form-data',
        },
      ),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );

    return _parse<T>(resp, parser);
  }

  // --------------- Helpers ---------------

  void _recordDioErrorTelemetry(DioException err) {
    final endpoint = bucketEndpoint(err.requestOptions.path);
    if (isTelemetryEndpoint(endpoint)) return;

    final method = err.requestOptions.method.toUpperCase();

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      recordHttpTimeout(
        source: 'dio',
        method: method,
        endpoint: endpoint,
        timeoutMs: _dioTimeoutMs(err),
      );
      return;
    }

    if (err.type == DioExceptionType.connectionError ||
        err.error is SocketException) {
      recordHttpNetworkError(
        source: 'dio',
        method: method,
        endpoint: endpoint,
        statusCode: err.response?.statusCode ?? 0,
        errorType: err.error is SocketException ? 'socket' : 'connection',
      );
      return;
    }

    if (err.response == null &&
        err.type == DioExceptionType.unknown &&
        isNetworkError(err.error ?? err)) {
      recordHttpNetworkError(
        source: 'dio',
        method: method,
        endpoint: endpoint,
        errorType: networkErrorType(err.error ?? err),
      );
    }
  }

  int? _dioTimeoutMs(DioException err) {
    final timeout = err.requestOptions.connectTimeout ??
        err.requestOptions.sendTimeout ??
        err.requestOptions.receiveTimeout;
    return timeout?.inMilliseconds;
  }

  T _parse<T>(Response resp, T Function(dynamic json)? parser) {
    final code = resp.statusCode ?? 0;

    if (code >= 200 && code < 300) {
      final data = resp.data;
      if (parser != null) {
        return parser(data);
      }
      return data as T;
    }

    // If we ever get here, convert into ApiException
    throw _asException(resp);
  }

  DioException _asDioError(Response resp) {
    return DioException(
      requestOptions: resp.requestOptions,
      response: resp,
      type: DioExceptionType.badResponse,
      error: _asException(resp),
    );
  }

  ApiException _asException(Response resp) {
    final status = resp.statusCode;
    final data = resp.data;
    final message = _extractMessage(data) ?? 'HTTP $status';
    final code = _extractCode(data);
    return ApiException(
      status: status,
      message: message,
      data: data,
      code: code,
    );
  }

  DioException _normalizeDioError(DioException err) {
    // If server responded, convert to ApiException but keep as DioException
    final resp = err.response;
    if (resp != null) {
      return DioException(
        requestOptions: err.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: _asException(resp), // wrap your ApiException
      );
    }

    // No response: map common network situations
    ApiException api;

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      api = ApiException(message: 'Network timeout');
      return DioException(
        requestOptions: err.requestOptions,
        type: err.type,
        error: api,
      );
    }

    if (err.type == DioExceptionType.cancel) {
      api = ApiException(message: 'Request cancelled');
      return DioException(
        requestOptions: err.requestOptions,
        type: DioExceptionType.cancel,
        error: api,
      );
    }

    if (err.error is SocketException) {
      api = ApiException(message: 'No internet connection');
      return DioException(
        requestOptions: err.requestOptions,
        type: DioExceptionType.connectionError,
        error: api,
      );
    }

    // Fallback
    api = ApiException(message: 'Network error: ${err.message}');
    return DioException(
      requestOptions: err.requestOptions,
      type: DioExceptionType.unknown,
      error: api,
    );
  }

  String? _extractMessage(dynamic data) {
    if (data is Map) {
      return (data['message'] ?? data['error'] ?? data['detail'])?.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  String? _extractCode(dynamic data) {
    if (data is Map && data['code'] != null) return data['code'].toString();
    return null;
  }

  Future<Response> _retryWithToken(RequestOptions req, String token) async {
    final newHeaders = Map<String, dynamic>.from(req.headers);
    newHeaders['Authorization'] = 'Bearer $token';

    final opts = Options(
      method: req.method,
      headers: newHeaders,
      responseType: req.responseType,
      contentType: req.contentType,
      followRedirects: req.followRedirects,
      validateStatus: req.validateStatus,
      receiveDataWhenStatusError: req.receiveDataWhenStatusError,
      extra: {...req.extra, '__ret': true},
    );

    return _dio.request(
      req.path,
      data: req.data,
      queryParameters: req.queryParameters,
      options: opts,
      cancelToken: req.cancelToken,
      onSendProgress: req.onSendProgress,
      onReceiveProgress: req.onReceiveProgress,
    );
  }
}
