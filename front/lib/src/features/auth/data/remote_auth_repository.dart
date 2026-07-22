import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/session_store.dart';
import '../domain/app_user.dart';
import '../domain/auth_session.dart';
import 'auth_repository.dart';

class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository({
    required Dio client,
    required SessionStore sessionStore,
  })  : _client = client,
        _sessionStore = sessionStore;

  final Dio _client;
  final SessionStore _sessionStore;

  @override
  Future<AuthSession?> restoreSession() async {
    final accessToken = await _sessionStore.readAccessToken();
    final refreshToken = await _sessionStore.readRefreshToken();

    if (accessToken == null || refreshToken == null) {
      return null;
    }

    try {
      final response = await _client.get<Map<String, dynamic>>('/api/auth/me');
      final data = response.data ?? <String, dynamic>{};
      final userPayload = switch (data['user']) {
        final Map<String, dynamic> user => user,
        _ => data,
      };
      final currentAccessToken =
          await _sessionStore.readAccessToken() ?? accessToken;
      final currentRefreshToken =
          await _sessionStore.readRefreshToken() ?? refreshToken;

      return AuthSession(
        accessToken: currentAccessToken,
        refreshToken: currentRefreshToken,
        user: AppUser.fromJson(userPayload),
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ?? 'No se pudo restaurar la sesion.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: <String, String>{
          'identifier': identifier,
          'password': password,
        },
      );

      final data = response.data ?? <String, dynamic>{};
      final accessToken = data['accessToken'] as String? ?? '';
      final refreshToken = data['refreshToken'] as String? ?? '';
      final userPayload =
          data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};

      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw const ApiException('La respuesta de autenticacion es invalida.');
      }

      await _sessionStore.writeSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      return AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: AppUser.fromJson(userPayload),
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ??
            'Credenciales invalidas o backend inaccesible.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<AuthSession> changePassword({
    required AuthSession currentSession,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/auth/change-password',
        data: <String, String>{
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
      final data = response.data ?? <String, dynamic>{};
      final userPayload =
          data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};

      return currentSession.copyWith(
        user: AppUser.fromJson(userPayload),
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ??
            'No se pudo actualizar la contrasena.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _sessionStore.readRefreshToken();

    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _client.post<void>(
          '/api/auth/logout',
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
      }
    } finally {
      await _sessionStore.clear();
    }
  }
}
