import '../../../core/utils/semantic_version.dart';
import 'app_version.dart';

enum AppPrimaryAction { install, update, open, none }

class CorporateApp {
  const CorporateApp({
    required this.id,
    required this.name,
    required this.packageName,
    required this.description,
    required this.iconPath,
    required this.installedVersion,
    required this.installedVersionCode,
    required this.latestVersion,
    required this.isInstalled,
    required this.updateAvailable,
    required this.status,
    required this.requiresExplicitAccess,
  });

  final String id;
  final String name;
  final String packageName;
  final String description;
  final String iconPath;
  final String? installedVersion;
  final int? installedVersionCode;
  final AppVersion? latestVersion;
  final bool isInstalled;
  final bool updateAvailable;
  final String status;
  final bool requiresExplicitAccess;

  bool get isMandatoryUpdate =>
      latestVersion?.mandatory == true && hasUpdateAvailable;
  bool get isBelowMinimumSupportedVersion {
    final minimumSupportedVersionCode = latestVersion?.minSupportedVersionCode;

    if (!isInstalled ||
        minimumSupportedVersionCode == null ||
        installedVersionCode == null) {
      return false;
    }

    return installedVersionCode! < minimumSupportedVersionCode;
  }

  bool get requiresImmediateUpdate {
    if (!isInstalled || !hasUpdateAvailable) {
      return false;
    }

    return isMandatoryUpdate || isBelowMinimumSupportedVersion;
  }

  AppPrimaryAction get primaryAction {
    if (latestVersion == null) {
      return AppPrimaryAction.none;
    }

    if (!isInstalled || installedVersion == null) {
      return AppPrimaryAction.install;
    }

    final installed = SemanticVersion.parse(installedVersion!);
    final latest = SemanticVersion.parse(latestVersion!.version);

    if (installed.compareTo(latest) < 0) {
      return AppPrimaryAction.update;
    }

    return AppPrimaryAction.open;
  }

  bool get hasUpdateAvailable {
    if (updateAvailable) {
      return true;
    }

    if (latestVersion == null) {
      return false;
    }

    if (!isInstalled || installedVersion == null) {
      return false;
    }

    return SemanticVersion.parse(installedVersion!).compareTo(
          SemanticVersion.parse(latestVersion!.version),
        ) <
        0;
  }

  CorporateApp copyWith({
    String? installedVersion,
    int? installedVersionCode,
    AppVersion? latestVersion,
    bool? isInstalled,
    bool? updateAvailable,
  }) {
    return CorporateApp(
      id: id,
      name: name,
      packageName: packageName,
      description: description,
      iconPath: iconPath,
      installedVersion: installedVersion ?? this.installedVersion,
      installedVersionCode: installedVersionCode ?? this.installedVersionCode,
      latestVersion: latestVersion ?? this.latestVersion,
      isInstalled: isInstalled ?? this.isInstalled,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      status: status,
      requiresExplicitAccess: requiresExplicitAccess,
    );
  }

  factory CorporateApp.fromJson(Map<String, dynamic> json) {
    final installedState = json['installedState'] as Map<String, dynamic>?;
    final latestVersionPayload = json['latestVersion'];
    final installedStatus = installedState?['status'] as String?;
    final isInstalled = (json['isInstalled'] as bool?) ??
        (installedStatus != null &&
            installedStatus != 'NOT_INSTALLED' &&
            installedStatus != 'UNKNOWN' &&
            installedStatus != 'INSTALL_FAILED');

    return CorporateApp(
      id: json['id'] as String,
      name: (json['displayName'] as String?) ?? (json['name'] as String? ?? ''),
      packageName: json['packageName'] as String? ?? '',
      description: (json['shortDescription'] as String?) ??
          (json['description'] as String? ?? ''),
      iconPath:
          (json['iconPath'] as String?) ?? (json['iconUrl'] as String? ?? ''),
      installedVersion: (installedState?['installedVersionName'] as String?) ??
          (json['installedVersion'] as String?),
      installedVersionCode: _parseInt(
        installedState?['installedVersionCode'] ?? json['installedVersionCode'],
      ),
      latestVersion: latestVersionPayload is Map<String, dynamic>
          ? AppVersion.fromJson(latestVersionPayload,
              appId: json['id'] as String)
          : null,
      isInstalled: isInstalled,
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      status: json['status'] as String? ?? 'UNKNOWN',
      requiresExplicitAccess: json['requiresExplicitAccess'] as bool? ?? false,
    );
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
