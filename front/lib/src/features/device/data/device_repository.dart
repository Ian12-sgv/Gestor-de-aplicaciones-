import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../domain/device_profile.dart';

abstract class DeviceRepository {
  Future<DeviceProfile> getOrCreateProfile();
  Future<DeviceProfile> registerDevice(DeviceProfile profile);
  Future<void> reportInstallation({
    required String deviceId,
    required String appId,
    String? appVersionId,
    int? installedVersionCode,
    String? installedVersionName,
    required String action,
    required String status,
    String? notes,
    String? deviceAppStatus,
  });
}

class LocalDeviceRepository implements DeviceRepository {
  LocalDeviceRepository();

  static final _uuid = Uuid();
  static const _deviceIdentifierKey = 'device.identifier';
  static const _registeredDeviceIdKey = 'device.registeredId';

  @override
  Future<DeviceProfile> getOrCreateProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final existingIdentifier = prefs.getString(_deviceIdentifierKey);
    final existingRegisteredDeviceId = prefs.getString(_registeredDeviceIdKey);
    final deviceIdentifier = existingIdentifier ?? _uuid.v4();

    if (existingIdentifier == null) {
      await prefs.setString(_deviceIdentifierKey, deviceIdentifier);
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final osVersion = _truncate(Platform.operatingSystemVersion, 50);

    return DeviceProfile(
      deviceIdentifier: deviceIdentifier,
      displayName: 'Dispositivo corporativo',
      platform: 'Android',
      deviceId: existingRegisteredDeviceId,
      osVersion: osVersion,
      appVersionName: packageInfo.version,
    );
  }

  @override
  Future<DeviceProfile> registerDevice(DeviceProfile profile) async {
    return profile;
  }

  @override
  Future<void> reportInstallation({
    required String deviceId,
    required String appId,
    String? appVersionId,
    int? installedVersionCode,
    String? installedVersionName,
    required String action,
    required String status,
    String? notes,
    String? deviceAppStatus,
  }) async {
    return;
  }

  Future<void> persistRegisteredDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredDeviceIdKey, deviceId);
  }

  static String? _truncate(String? value, int maxLength) {
    if (value == null || value.isEmpty) {
      return value;
    }

    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }
}

class RemoteDeviceRepository implements DeviceRepository {
  RemoteDeviceRepository({
    required Dio client,
    required LocalDeviceRepository localRepository,
  })  : _client = client,
        _localRepository = localRepository;

  final Dio _client;
  final LocalDeviceRepository _localRepository;

  @override
  Future<DeviceProfile> getOrCreateProfile() {
    return _localRepository.getOrCreateProfile();
  }

  @override
  Future<DeviceProfile> registerDevice(DeviceProfile profile) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/devices/register',
        data: <String, Object?>{
          'deviceIdentifier': profile.deviceIdentifier,
          'name': profile.displayName,
          'osVersion': profile.osVersion,
          'appVersionName': profile.appVersionName,
          'status': 'ACTIVE',
        },
      );

      final payload = response.data?['device'] as Map<String, dynamic>? ??
          <String, dynamic>{};
      final registeredDeviceId = payload['id'] as String? ?? '';

      if (registeredDeviceId.isEmpty) {
        throw const ApiException(
            'La respuesta de registro del dispositivo es invalida.');
      }

      await _localRepository.persistRegisteredDeviceId(registeredDeviceId);

      return profile.copyWith(
        deviceId: registeredDeviceId,
        displayName: payload['name'] as String? ?? profile.displayName,
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ??
            'No se pudo registrar el dispositivo.',
        statusCode: error.response?.statusCode,
      );
    }
  }

  @override
  Future<void> reportInstallation({
    required String deviceId,
    required String appId,
    String? appVersionId,
    int? installedVersionCode,
    String? installedVersionName,
    required String action,
    required String status,
    String? notes,
    String? deviceAppStatus,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/devices/report-installation',
        data: <String, Object?>{
          'deviceId': deviceId,
          'appId': appId,
          'appVersionId': appVersionId,
          'installedVersionCode': installedVersionCode,
          'installedVersionName': installedVersionName,
          'action': action,
          'status': status,
          'notes': notes,
          'deviceAppStatus': deviceAppStatus,
        },
      );
    } on DioException catch (error) {
      throw ApiException(
        error.response?.data?.toString() ??
            'No se pudo reportar el estado de instalacion.',
        statusCode: error.response?.statusCode,
      );
    }
  }
}
