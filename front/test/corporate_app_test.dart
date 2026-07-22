import 'package:flutter_test/flutter_test.dart';

import 'package:corporate_app_store/src/features/apps/domain/app_version.dart';
import 'package:corporate_app_store/src/features/apps/domain/corporate_app.dart';

void main() {
  group('CorporateApp forced update UX', () {
    test('marks a mandatory update as immediate when installed version is outdated', () {
      final app = _buildApp(
        installedVersion: '1.0.0',
        installedVersionCode: 100,
        latestVersion: _buildVersion(
          versionName: '1.1.0',
          versionCode: 110,
          isMandatory: true,
        ),
        isInstalled: true,
        updateAvailable: true,
      );

      expect(app.isMandatoryUpdate, isTrue);
      expect(app.requiresImmediateUpdate, isTrue);
    });

    test('marks an update as immediate when below minimum supported version', () {
      final app = _buildApp(
        installedVersion: '1.0.0',
        installedVersionCode: 90,
        latestVersion: _buildVersion(
          versionName: '1.2.0',
          versionCode: 120,
          minSupportedVersionCode: 100,
        ),
        isInstalled: true,
        updateAvailable: true,
      );

      expect(app.isBelowMinimumSupportedVersion, isTrue);
      expect(app.requiresImmediateUpdate, isTrue);
    });

    test('does not mark optional updates as immediate', () {
      final app = _buildApp(
        installedVersion: '1.0.0',
        installedVersionCode: 100,
        latestVersion: _buildVersion(
          versionName: '1.1.0',
          versionCode: 110,
        ),
        isInstalled: true,
        updateAvailable: true,
      );

      expect(app.isMandatoryUpdate, isFalse);
      expect(app.isBelowMinimumSupportedVersion, isFalse);
      expect(app.requiresImmediateUpdate, isFalse);
    });
  });
}

CorporateApp _buildApp({
  required String? installedVersion,
  required int? installedVersionCode,
  required AppVersion latestVersion,
  required bool isInstalled,
  required bool updateAvailable,
}) {
  return CorporateApp(
    id: 'app-id',
    name: 'Ventas PDA',
    packageName: 'com.company.sales',
    description: 'App de prueba',
    iconPath: '',
    installedVersion: installedVersion,
    installedVersionCode: installedVersionCode,
    latestVersion: latestVersion,
    isInstalled: isInstalled,
    updateAvailable: updateAvailable,
    status: 'ACTIVE',
    requiresExplicitAccess: false,
  );
}

AppVersion _buildVersion({
  required String versionName,
  required int versionCode,
  bool isMandatory = false,
  int? minSupportedVersionCode,
}) {
  return AppVersion(
    id: 'version-id',
    versionName: versionName,
    versionCode: versionCode,
    changelog: '',
    releaseDateIso: '2026-04-23',
    isMandatory: isMandatory,
    downloadPath: '/api/apps/app-id/download',
    minSupportedVersionCode: minSupportedVersionCode,
  );
}
