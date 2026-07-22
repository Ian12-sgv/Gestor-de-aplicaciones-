import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_store.dart';

class ApiClient {
  ApiClient({
    required AppConfig config,
    required SessionStore sessionStore,
  })  : _sessionStore = sessionStore,
        _baseOptions = BaseOptions(
          baseUrl: config.apiBaseUrl.toString(),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: const <String, Object>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
        dio = Dio(
          BaseOptions(
            baseUrl: config.apiBaseUrl.toString(),
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: const <String, Object>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        ) {
    _refreshClient = Dio(_baseOptions);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] == true) {
            handler.next(options);
            return;
          }

          final token = await _sessionStore.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (!await _shouldRefresh(error)) {
            handler.next(error);
            return;
          }

          final refreshedAccessToken = await _refreshAccessToken();
          if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
            handler.next(error);
            return;
          }

          try {
            final requestOptions = error.requestOptions;
            final retriedRequest = requestOptions.copyWith(
              headers: <String, dynamic>{
                ...requestOptions.headers,
                'Authorization': 'Bearer $refreshedAccessToken',
              },
              extra: <String, dynamic>{
                ...requestOptions.extra,
                'retryAttempted': true,
              },
            );

            final response = await dio.fetch<dynamic>(retriedRequest);
            handler.resolve(response);
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }

  final Dio dio;
  final SessionStore _sessionStore;
  final BaseOptions _baseOptions;
  late final Dio _refreshClient;
  Future<String?>? _refreshInFlight;

  Future<bool> _shouldRefresh(DioException error) async {
    final response = error.response;
    final requestOptions = error.requestOptions;
    final path = requestOptions.path;

    if (response?.statusCode != 401) {
      return false;
    }

    if (requestOptions.extra['retryAttempted'] == true ||
        requestOptions.extra['skipRefresh'] == true) {
      return false;
    }

    if (path.endsWith('/auth/login') ||
        path.endsWith('/auth/refresh') ||
        path.endsWith('/auth/logout')) {
      return false;
    }

    final refreshToken = await _sessionStore.readRefreshToken();
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  Future<String?> _refreshAccessToken() {
    final existingRefresh = _refreshInFlight;
    if (existingRefresh != null) {
      return existingRefresh;
    }

    final future = _performRefresh();
    _refreshInFlight = future;

    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });

    return future;
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _sessionStore.clear();
      return null;
    }

    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: <String, String>{
          'refreshToken': refreshToken,
        },
        options: Options(
          extra: const <String, Object>{
            'skipAuth': true,
            'skipRefresh': true,
          },
        ),
      );

      final data = response.data ?? <String, dynamic>{};
      final nextAccessToken = data['accessToken'] as String? ?? '';
      final nextRefreshToken = data['refreshToken'] as String? ?? '';

      if (nextAccessToken.isEmpty || nextRefreshToken.isEmpty) {
        await _sessionStore.clear();
        return null;
      }

      await _sessionStore.writeSession(
        accessToken: nextAccessToken,
        refreshToken: nextRefreshToken,
      );

      return nextAccessToken;
    } on DioException {
      await _sessionStore.clear();
      return null;
    }
  }
}
