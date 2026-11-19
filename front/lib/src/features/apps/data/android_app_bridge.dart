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
  signatureConflict,
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

class BackgroundDownloadResult {
  const BackgroundDownloadResult({
    required this.queued,
    required this.message,
    this.downloadId,
    this.filePath,
  });

  final bool queued;
  final String message;
  final int? downloadId;
  final String? filePath;
}

class BackgroundDownloadProgress {
  const BackgroundDownloadProgress({
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int status;
  final int receivedBytes;
  final int totalBytes;

  bool get isSuccessful => status == 8;
  bool get isFinished => status == 8 || status == 16;
  double? get fraction => totalBytes > 0
      ? (receivedBytes / totalBytes).clamp(0, 1).toDouble()
      : null;
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

  Future<bool> ensureNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'ensureNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<BackgroundDownloadResult> enqueueApkDownload({
    required Uri downloadUri,
    String? accessToken,
    required String fileName,
    required String appName,
    required String packageName,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'enqueueApkDownload',
        <String, Object?>{
          'downloadUrl': downloadUri.toString(),
          'accessToken': accessToken,
          'fileName': fileName,
          'appName': appName,
          'packageName': packageName,
        },
      );
      final status = result?['status'] as String? ?? 'unavailable';
      return BackgroundDownloadResult(
        queued: status == 'queued',
        message: result?['message'] as String? ??
            'No se pudo iniciar la descarga en segundo plano.',
        downloadId: _parseInt(result?['downloadId']),
        filePath: result?['filePath'] as String?,
      );
    } on PlatformException catch (error) {
      return BackgroundDownloadResult(
        queued: false,
        message:
            error.message ?? 'No se pudo iniciar la descarga en segundo plano.',
      );
    }
  }

  Future<BackgroundDownloadProgress?> getApkDownloadProgress(
    int downloadId,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getApkDownloadProgress',
        <String, Object?>{'downloadId': downloadId},
      );
      if (result == null) {
        return null;
      }
      return BackgroundDownloadProgress(
        status: _parseInt(result['status']) ?? 16,
        receivedBytes: _parseInt(result['receivedBytes']) ?? 0,
        totalBytes: _parseInt(result['totalBytes']) ?? -1,
      );
    } on PlatformException {
      return null;
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
        status: _parseInstallStatus(statusValue),
        message: message,
      );
    } on PlatformException catch (error) {
      return InstallLaunchResult(
        status: InstallLaunchStatus.unavailable,
        message: error.message ?? 'No fue posible iniciar la instalacion.',
      );
    }
  }

  /// Opens the system installer for a finished background download. Returns
  /// `deferred` when the store is not on screen; the notification handles it then.
  Future<InstallLaunchResult?> installDownloadedApk({
    required int downloadId,
    required String apkPath,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'installDownloadedApk',
        <String, Object?>{'downloadId': downloadId, 'apkPath': apkPath},
      );
      final statusValue = result?['status'] as String? ?? 'unavailable';
      if (statusValue == 'deferred') {
        return null;
      }
      return InstallLaunchResult(
        status: _parseInstallStatus(statusValue),
        message: result?['message'] as String? ??
            'No fue posible iniciar la instalacion.',
      );
    } on PlatformException catch (error) {
      return InstallLaunchResult(
        status: InstallLaunchStatus.unavailable,
        message: error.message ?? 'No fue posible iniciar la instalacion.',
      );
    }
  }

  static InstallLaunchStatus _parseInstallStatus(String value) {
    return switch (value) {
      'launchedInstaller' => InstallLaunchStatus.launchedInstaller,
      'needsPermission' => InstallLaunchStatus.needsPermission,
      'signatureConflict' => InstallLaunchStatus.signatureConflict,
      _ => InstallLaunchStatus.unavailable,
    };
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
