import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../device/data/device_repository.dart';
import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../domain/corporate_app.dart';
import 'android_app_bridge.dart';

final androidAppBridgeProvider = Provider<AndroidAppBridge>((ref) {
  return AndroidAppBridge();
});

final appRuntimeServiceProvider = Provider<AppRuntimeService>((ref) {
  return AppRuntimeService(
    client: ref.watch(apiClientProvider).dio,
    deviceRepository: ref.watch(deviceRepositoryProvider),
    androidAppBridge: ref.watch(androidAppBridgeProvider),
  );
});

final installEnvironmentInfoProvider =
    FutureProvider<InstallEnvironmentInfo>((ref) {
  return ref.watch(androidAppBridgeProvider).getInstallEnvironmentInfo();
});

class AppActionResult {
  const AppActionResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class AppRuntimeService {
  AppRuntimeService({
    required Dio client,
    required DeviceRepository deviceRepository,
    required AndroidAppBridge androidAppBridge,
  })  : _client = client,
        _deviceRepository = deviceRepository,
        _androidAppBridge = androidAppBridge;

  final Dio _client;
  final DeviceRepository _deviceRepository;
  final AndroidAppBridge _androidAppBridge;

  Future<List<CorporateApp>> enrichAndSyncApps(
    List<CorporateApp> apps, {
    DeviceProfile? deviceProfile,
  }) async {
    final installedApps = await _loadInstalledApps(apps);

    if (deviceProfile?.deviceId != null) {
      await _syncDeviceStates(
        apps: apps,
        installedApps: installedApps,
        deviceId: deviceProfile!.deviceId!,
      );
    }

    return apps.map((app) {
      final installedApp = installedApps[app.packageName];
      return _applyInstalledState(app, installedApp);
    }).toList(growable: false);
  }

  Future<CorporateApp> enrichAndSyncApp(
    CorporateApp app, {
    DeviceProfile? deviceProfile,
  }) async {
    final enrichedApps = await enrichAndSyncApps(
      <CorporateApp>[app],
      deviceProfile: deviceProfile,
    );

    return enrichedApps.first;
  }

  Future<AppActionResult> openInstalledApp(
    CorporateApp app, {
    required DeviceProfile? deviceProfile,
  }) async {
    final deviceId = deviceProfile?.deviceId;
    final installedApp =
        (await _loadInstalledApps(<CorporateApp>[app]))[app.packageName];

    if (installedApp == null || !installedApp.installed) {
      if (deviceId != null) {
        await _safeReport(
          deviceId: deviceId,
          appId: app.id,
          action: 'OPEN',
          status: 'FAILED',
          notes: 'La app no esta instalada en este dispositivo.',
          deviceAppStatus: 'NOT_INSTALLED',
        );
      }

      return const AppActionResult(
        success: false,
        message: 'La app no esta instalada en este dispositivo.',
      );
    }

    final launched = await _androidAppBridge.openApp(app.packageName);

    if (deviceId != null) {
      await _safeReport(
        deviceId: deviceId,
        appId: app.id,
        appVersionId: _resolveAppVersionId(app, installedApp),
        installedVersionCode: installedApp.versionCode,
        installedVersionName: installedApp.versionName,
        action: 'OPEN',
        status: launched ? 'SUCCESS' : 'FAILED',
        notes: launched ? null : 'No fue posible abrir la app instalada.',
        deviceAppStatus: 'INSTALLED',
      );
    }

    return AppActionResult(
      success: launched,
      message: launched
          ? 'Se abrio la app instalada.'
          : 'No fue posible abrir la app instalada.',
    );
  }

  Future<AppActionResult> uninstallApp(
    CorporateApp app, {
    required DeviceProfile? deviceProfile,
  }) async {
    final deviceId = deviceProfile?.deviceId;
    final installedApp =
        (await _loadInstalledApps(<CorporateApp>[app]))[app.packageName];

    if (installedApp == null || !installedApp.installed) {
      if (deviceId != null) {
        await _safeReport(
          deviceId: deviceId,
          appId: app.id,
          action: 'REMOVE',
          status: 'FAILED',
          notes: 'La app no esta instalada en este dispositivo.',
          deviceAppStatus: 'NOT_INSTALLED',
        );
      }

      return const AppActionResult(
        success: false,
        message: 'La app no esta instalada en este dispositivo.',
      );
    }

    final uninstallResult =
        await _androidAppBridge.uninstallApp(app.packageName);
    final launched =
        uninstallResult.status == UninstallLaunchStatus.launchedUninstaller;

    if (deviceId != null) {
      await _safeReport(
        deviceId: deviceId,
        appId: app.id,
        appVersionId: _resolveAppVersionId(app, installedApp),
        installedVersionCode: installedApp.versionCode,
        installedVersionName: installedApp.versionName,
        action: 'REMOVE',
        status: launched ? 'PENDING' : 'FAILED',
        notes: uninstallResult.message,
        deviceAppStatus: installedApp.installed ? 'INSTALLED' : 'NOT_INSTALLED',
      );
    }

    return AppActionResult(
      success: launched,
      message: uninstallResult.message,
    );
  }

  Future<AppActionResult> downloadAndInstall(
    CorporateApp app, {
    required DeviceProfile? deviceProfile,
    void Function(double? progress)? onDownloadProgress,
  }) async {
    final latestVersion = app.latestVersion;

    if (latestVersion == null) {
      return const AppActionResult(
        success: false,
        message: 'No hay una version disponible para instalar.',
      );
    }

    final apkDirectoryPath = await _androidAppBridge.getApkCacheDirectory();
    final apkDirectory = Directory(
      apkDirectoryPath?.trim().isNotEmpty == true
          ? apkDirectoryPath!
          : '${Directory.systemTemp.path}${Platform.pathSeparator}corporate_store_apks',
    );
    await apkDirectory.create(recursive: true);

    final fileName =
        '${_sanitizeFileName(app.packageName)}-${latestVersion.versionCode}.apk';
    final apkFile =
        File('${apkDirectory.path}${Platform.pathSeparator}$fileName');
    final deviceId = deviceProfile?.deviceId;
    final installAction =
        app.primaryAction == AppPrimaryAction.update ? 'UPDATE' : 'INSTALL';

    try {
      onDownloadProgress?.call(0);
      await _client.download(
        latestVersion.downloadPath,
        apkFile.path,
        queryParameters: deviceId == null
            ? null
            : <String, Object?>{
                'deviceId': deviceId,
              },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) {
            onDownloadProgress?.call(null);
            return;
          }

          final progress = (received / total).clamp(0, 1).toDouble();
          onDownloadProgress?.call(progress);
        },
      );
      onDownloadProgress?.call(1);
    } on DioException catch (error) {
      if (deviceId != null) {
        await _safeReport(
          deviceId: deviceId,
          appId: app.id,
          appVersionId: latestVersion.id,
          installedVersionCode: latestVersion.versionCode,
          installedVersionName: latestVersion.versionName,
          action: 'DOWNLOAD',
          status: 'FAILED',
          notes: error.message ?? 'No se pudo descargar la app.',
          deviceAppStatus: app.isInstalled ? 'INSTALLED' : 'NOT_INSTALLED',
        );
      }

      return AppActionResult(
        success: false,
        message: error.message ?? 'No se pudo descargar la app.',
      );
    }

    final installResult = await _androidAppBridge.installApk(apkFile.path);

    if (deviceId != null) {
      await _safeReport(
        deviceId: deviceId,
        appId: app.id,
        appVersionId: latestVersion.id,
        installedVersionCode: latestVersion.versionCode,
        installedVersionName: latestVersion.versionName,
        action: installAction,
        status: installResult.status == InstallLaunchStatus.launchedInstaller
            ? 'PENDING'
            : 'FAILED',
        notes: installResult.message,
        deviceAppStatus: app.isInstalled ? 'INSTALLED' : 'NOT_INSTALLED',
      );
    }

    final resolvedMessage = _resolveInstallMessage(
      installResult: installResult,
    );

    return AppActionResult(
      success: installResult.status == InstallLaunchStatus.launchedInstaller,
      message: resolvedMessage,
    );
  }

  Future<Map<String, InstalledAppInfo>> _loadInstalledApps(
      List<CorporateApp> apps) {
    return _androidAppBridge.getInstalledAppsInfo(
      apps.map((app) => app.packageName).toSet().toList(growable: false),
    );
  }

  Future<void> _syncDeviceStates({
    required List<CorporateApp> apps,
    required Map<String, InstalledAppInfo> installedApps,
    required String deviceId,
  }) async {
    for (final app in apps) {
      final installedApp = installedApps[app.packageName];
      if (installedApp == null) {
        continue;
      }

      if (installedApp.installed) {
        final backendKnowsInstalled = app.isInstalled;
        final versionChanged = backendKnowsInstalled &&
            ((app.installedVersionCode != null &&
                    installedApp.versionCode != null &&
                    app.installedVersionCode != installedApp.versionCode) ||
                ((app.installedVersionCode == null ||
                        installedApp.versionCode == null) &&
                    app.installedVersion != installedApp.versionName));

        if (!backendKnowsInstalled || versionChanged) {
          await _safeReport(
            deviceId: deviceId,
            appId: app.id,
            appVersionId: _resolveAppVersionId(app, installedApp),
            installedVersionCode: installedApp.versionCode,
            installedVersionName: installedApp.versionName,
            action: backendKnowsInstalled ? 'UPDATE' : 'INSTALL',
            status: 'SUCCESS',
            deviceAppStatus: 'INSTALLED',
          );
        }
      } else if (app.isInstalled) {
        await _safeReport(
          deviceId: deviceId,
          appId: app.id,
          action: 'REMOVE',
          status: 'SUCCESS',
          deviceAppStatus: 'NOT_INSTALLED',
          notes: 'La app ya no aparece instalada localmente.',
        );
      }
    }
  }

  Future<void> _safeReport({
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
      await _deviceRepository.reportInstallation(
        deviceId: deviceId,
        appId: appId,
        appVersionId: appVersionId,
        installedVersionCode: installedVersionCode,
        installedVersionName: installedVersionName,
        action: action,
        status: status,
        notes: notes,
        deviceAppStatus: deviceAppStatus,
      );
    } catch (_) {
      return;
    }
  }

  CorporateApp _applyInstalledState(
      CorporateApp app, InstalledAppInfo? installedApp) {
    if (installedApp == null) {
      return app;
    }

    final latestVersionCode = app.latestVersion?.versionCode;
    final localUpdateAvailable = installedApp.installed &&
        latestVersionCode != null &&
        installedApp.versionCode != null &&
        installedApp.versionCode! < latestVersionCode;

    return app.copyWith(
      installedVersion:
          installedApp.installed ? installedApp.versionName : null,
      installedVersionCode:
          installedApp.installed ? installedApp.versionCode : null,
      isInstalled: installedApp.installed,
      updateAvailable: app.updateAvailable || localUpdateAvailable,
    );
  }

  String? _resolveAppVersionId(
      CorporateApp app, InstalledAppInfo installedApp) {
    final latestVersion = app.latestVersion;

    if (latestVersion == null) {
      return null;
    }

    if (installedApp.versionCode != null &&
        installedApp.versionCode == latestVersion.versionCode) {
      return latestVersion.id;
    }

    if (installedApp.versionName != null &&
        installedApp.versionName == latestVersion.versionName) {
      return latestVersion.id;
    }

    return null;
  }

  static String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _resolveInstallMessage({
    required InstallLaunchResult installResult,
  }) {
    return switch (installResult.status) {
      InstallLaunchStatus.launchedInstaller =>
        'Sigue los pasos de Android para completar la instalacion.',
      InstallLaunchStatus.needsPermission =>
        'Android necesita permiso para instalar apps corporativas. Activalo y vuelve a intentar.',
      InstallLaunchStatus.unavailable =>
        'No se pudo abrir el instalador de Android en este dispositivo.',
    };
  }
}
