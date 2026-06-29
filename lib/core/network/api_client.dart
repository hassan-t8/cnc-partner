import 'package:dio/dio.dart';

import '../config/env.dart';

/// Thrown for normalized API errors with a friendly message + raw status/code.
class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  final dynamic data;
  ApiException(this.message, {this.status, this.code, this.data});
  @override
  String toString() => message;
}

typedef TokenProvider = String? Function();
typedef UnauthorizedHandler = void Function();

/// Dio wrapper: injects the bearer token, normalizes errors, and bubbles 401s
/// up to a handler (which clears the session and routes to login).
class ApiClient {
  final Dio _dio;
  TokenProvider? _tokenProvider;
  UnauthorizedHandler? _onUnauthorized;

  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: Env.apiUrl,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _tokenProvider?.call();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        // A 401 normally means the session expired → sign out. But some
        // endpoints (e.g. change-password) return 401 to mean "wrong
        // credential" — those opt out via extra['skipAuthRedirect'] so a
        // bad current password doesn't silently log the user out.
        final skip = e.requestOptions.extra['skipAuthRedirect'] == true;
        if (e.response?.statusCode == 401 && !skip) {
          _onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));
  }

  void configure({TokenProvider? token, UnauthorizedHandler? onUnauthorized}) {
    _tokenProvider = token;
    _onUnauthorized = onUnauthorized;
  }

  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: query));

  Future<Response<dynamic>> post(String path,
          {dynamic body, bool skipAuthRedirect = false}) =>
      _wrap(() => _dio.post(path,
          data: body,
          options: Options(extra: {'skipAuthRedirect': skipAuthRedirect})));

  Future<Response<dynamic>> put(String path,
          {dynamic body, bool skipAuthRedirect = false}) =>
      _wrap(() => _dio.put(path,
          data: body,
          options: Options(extra: {'skipAuthRedirect': skipAuthRedirect})));

  Future<Response<dynamic>> delete(String path, {dynamic body}) =>
      _wrap(() => _dio.delete(path, data: body));

  /// Multipart PUT/POST with an optional file. [fields] values are sent as
  /// strings; [filePath] (if given) is attached under [fileField].
  Future<Response<dynamic>> multipart(
    String path, {
    String method = 'PUT',
    Map<String, String> fields = const {},
    String? filePath,
    String fileField = 'uploadFile',
  }) async {
    final form = FormData.fromMap({
      ...fields,
      if (filePath != null && filePath.isNotEmpty)
        fileField: await MultipartFile.fromFile(filePath),
    });
    return _wrap(() => _dio.request(
          path,
          data: form,
          options: Options(method: method),
        ));
  }

  Future<Response<dynamic>> _wrap(
      Future<Response<dynamic>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _normalize(e);
    }
  }

  ApiException _normalize(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? code;
    String? serverMsg;
    if (data is Map) {
      code = (data['code'] ?? data['error'])?.toString();
      serverMsg = (data['message'] ?? data['error'])?.toString();
    }
    String msg;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      msg = "Can't reach the server. Please check your internet.";
    } else if (status == 401) {
      msg = 'Your session has expired. Please sign in again.';
    } else if (status == 403) {
      msg = 'You don\'t have access to that.';
    } else if (status != null && status >= 500) {
      msg = 'Server is temporarily unavailable. Please try again.';
    } else {
      msg = serverMsg ?? 'Something went wrong. Please try again.';
    }
    return ApiException(msg, status: status, code: code, data: data);
  }
}

/// Defensive list extraction across the backend's varied envelopes:
/// `[...]`, `{data:[...]}`, `{rows:[...]}`, `{bookings:[...]}`, `{data:{rows:[...]}}`.
List<Map<String, dynamic>> pickList(dynamic body) {
  dynamic d = body;
  if (d is List) return d.whereType<Map>().map(_asMap).toList();
  if (d is Map) {
    for (final key in ['data', 'rows', 'bookings', 'items', 'result']) {
      final v = d[key];
      if (v is List) return v.whereType<Map>().map(_asMap).toList();
      if (v is Map && v['rows'] is List) {
        return (v['rows'] as List).whereType<Map>().map(_asMap).toList();
      }
    }
  }
  return const [];
}

Map<String, dynamic> pickMap(dynamic body) {
  if (body is Map && body['data'] is Map) return _asMap(body['data']);
  if (body is Map) return _asMap(body);
  return const {};
}

Map<String, dynamic> _asMap(dynamic m) => Map<String, dynamic>.from(m as Map);
