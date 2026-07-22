import 'package:flutter/services.dart';

class InstalledAppInfo {
  const InstalledAppInfo({
    required this.installed,
    this.versionName,
    this.versionCode,
  });

  final bool installed;
  final String? versionName;
  final int? versionCode;
}

class InstallEnvironmentInfo {
  const InstallEnvironmentInfo({
    required this.manufacturer,
    required this.model,
    required this.sdkInt,
    required this.canInstallUnknownApps,
    required this.installerAvailable,
    required this.settingsAvailable,
    required this.policyHint,
  });

  final String manufacturer;
  final String model;
  final int sdkInt;
  final bool canInstallUnknownApps;
  final bool installerAvailable;
  final bool settingsAvailable;
  final String policyHint;

  String get deviceLabel => [manufacturer, model]
      .where((value) => value.trim().isNotEmpty)
      .join(' ')
      .trim();

  factory InstallEnvironmentInfo.unknown() {
    return const InstallEnvironmentInfo(
      manufacturer: 'Unknown',
      model: '',
      sdkInt: 0,
      canInstallUnknownApps: false,
      installerAvailable: false,
      settingsAvailable: false,
      policyHint:
          'No fue posible consultar la politica de instalacion del dispositivo.',
    );
  }
}

enum InstallLaunchStatus {
  launchedInstaller,
  needsPermission,
  unavailable,
}

enum UninstallLaunchStatus {
  launchedUninstaller,
  unavailable,
}

class InstallLaunchResult {
  const InstallLaunchResult({
    required this.status,
    required this.message,
  });

  final InstallLaunchStatus status;
  final String message;
}

class UninstallLaunchResult {
  const UninstallLaunchResult({
    required this.status,
    required this.message,
  });

  final UninstallLaunchStatus status;
  final String message;
}

class AndroidAppBridge {
  static const MethodChannel _channel =
      MethodChannel('corporate_app_store/android_apps');

  Future<Map<String, InstalledAppInfo>> getInstalledAppsInfo(
      List<String> packageNames) async {
    if (packageNames.isEmpty) {
      return const <String, InstalledAppInfo>{};
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInstalledAppsInfo',
        <String, Object?>{
          'packageNames': packageNames,
        },
      );

      if (result == null) {
        return const <String, InstalledAppInfo>{};
      }

      return result.map((key, value) {
        final payload = value is Map ? value : const <dynamic, dynamic>{};
        return MapEntry(
          key as String,
          InstalledAppInfo(
            installed: payload['installed'] as bool? ?? false,
            versionName: payload['versionName'] as String?,
            versionCode: _parseInt(payload['versionCode']),
          ),
        );
      });
    } on PlatformException {
      return const <String, InstalledAppInfo>{};
    }
  }

  Future<bool> openApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openApp',
        <String, Object?>{
          'packageName': packageName,
        },
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<UninstallLaunchResult> uninstallApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'uninstallApp',
        <String, Object?>{
          'packageName': packageName,
        },
      );

      final statusValue = result?['status'] as String? ?? 'unavailable';
      final message = result?['message'] as String? ??
          'No fue posible iniciar la desinstalacion.';

      return UninstallLaunchResult(
        status: statusValue == 'launchedUninstaller'
            ? UninstallLaunchStatus.launchedUninstaller
            : UninstallLaunchStatus.unavailable,
        message: message,
      );
    } on PlatformException catch (error) {
      return UninstallLaunchResult(
        status: UninstallLaunchStatus.unavailable,
        message: error.message ?? 'No fue posible iniciar la desinstalacion.',
      );
    }
  }

  Future<InstallLaunchResult> installApk(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'installApk',
        <String, Object?>{
          'apkPath': apkPath,
        },
      );

      final statusValue = result?['status'] as String? ?? 'unavailable';
      final message = result?['message'] as String? ??
          'No fue posible iniciar la instalacion.';

      return InstallLaunchResult(
        status: switch (statusValue) {
          'launchedInstaller' => InstallLaunchStatus.launchedInstaller,
          'needsPermission' => InstallLaunchStatus.needsPermission,
          _ => InstallLaunchStatus.unavailable,
        },
        message: message,
      );
    } on PlatformException catch (error) {
      return InstallLaunchResult(
        status: InstallLaunchStatus.unavailable,
        message: error.message ?? 'No fue posible iniciar la instalacion.',
      );
    }
  }

  Future<String?> getApkCacheDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getApkCacheDirectory');
    } on PlatformException {
      return null;
    }
  }

  Future<InstallEnvironmentInfo> getInstallEnvironmentInfo() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInstallEnvironmentInfo',
      );

      if (result == null) {
        return InstallEnvironmentInfo.unknown();
      }

      return InstallEnvironmentInfo(
        manufacturer: result['manufacturer'] as String? ?? 'Unknown',
        model: result['model'] as String? ?? '',
        sdkInt: _parseInt(result['sdkInt']) ?? 0,
        canInstallUnknownApps:
            result['canInstallUnknownApps'] as bool? ?? false,
        installerAvailable: result['installerAvailable'] as bool? ?? false,
        settingsAvailable: result['settingsAvailable'] as bool? ?? false,
        policyHint: result['policyHint'] as String? ??
            'No fue posible consultar la politica de instalacion del dispositivo.',
      );
    } on PlatformException {
      return InstallEnvironmentInfo.unknown();
    }
  }

  Future<bool> openInstallPermissionSettings() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('openInstallPermissionSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static int? _parseInt(Object? value) {
    return switch (value) {
      final int intValue => intValue,
      final num numValue => numValue.toInt(),
      final String stringValue => int.tryParse(stringValue),
      _ => null,
    };
  }
}
