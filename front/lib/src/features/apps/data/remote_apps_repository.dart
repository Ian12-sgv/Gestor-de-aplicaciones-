import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../domain/app_version.dart';
import '../domain/corporate_app.dart';
import 'apps_repository.dart';

class RemoteAppsRepository implements AppsRepository {
  RemoteAppsRepository({required Dio client}) : _client = client;

  final Dio _client;

  static final _publicOptions = Options(
    extra: <String, Object>{'skipAuth': true, 'skipRefresh': true},
  );

  @override
  Future<List<CorporateApp>> fetchApps({String? deviceId}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/apps',
        queryParameters: _deviceQuery(deviceId),
        options: _publicOptions,
      );
      final payload = response.data?['items'] as List<dynamic>? ?? <dynamic>[];
      return payload
          .whereType<Map<String, dynamic>>()
          .map(CorporateApp.fromJson)
          .toList(growable: false);
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ?? 'No se pudo cargar el catalogo.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<CorporateApp> fetchAppById(String id, {String? deviceId}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/apps/$id',
        queryParameters: _deviceQuery(deviceId),
        options: _publicOptions,
      );
      var app = CorporateApp.fromJson(response.data ?? <String, dynamic>{});

      if (app.latestVersion != null) {
        try {
          final latestVersion =
              await fetchLatestVersion(id, deviceId: deviceId);
          app = app.copyWith(latestVersion: latestVersion);
        } on ApiException catch (error) {
          if (error.statusCode != 404) {
            rethrow;
          }
        }
      }

      return app;
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ?? 'No se pudo cargar la app.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<AppVersion> fetchLatestVersion(String appId,
      {String? deviceId}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/apps/$appId/latest-version',
        queryParameters: _deviceQuery(deviceId),
        options: _publicOptions,
      );
      final data = response.data ?? <String, dynamic>{};
      final latestVersion =
          data['latestVersion'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final latestVersionAppId = data['appId'] as String? ?? appId;
      return AppVersion.fromJson(latestVersion, appId: latestVersionAppId);
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ?? 'No se pudo cargar la version.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<void> deleteAppFromStore(String appId) async {
    try {
      await _client.delete<Map<String, dynamic>>('/api/admin/apps/$appId');
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ??
            'No se pudo eliminar la app de la tienda.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  Map<String, Object?>? _deviceQuery(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }

    return <String, Object?>{
      'deviceId': deviceId,
    };
  }
}
