import '../domain/app_version.dart';
import '../domain/corporate_app.dart';
import 'apps_repository.dart';

class DemoAppsRepository implements AppsRepository {
  const DemoAppsRepository();

  @override
  Future<List<CorporateApp>> fetchApps({String? deviceId}) async {
    return <CorporateApp>[
      CorporateApp(
        id: 'inventory',
        name: 'Inventario Mobile',
        packageName: 'com.company.inventory',
        description:
            'Registro y consulta de inventario con sincronizacion segura.',
        iconPath: '',
        installedVersion: '1.2.0',
        installedVersionCode: 120,
        latestVersion: const AppVersion(
          id: 'inventory-1.3.0',
          versionName: '1.3.0',
          versionCode: 130,
          changelog: 'Mejoras en captura y validacion de stock.',
          releaseDateIso: '2026-04-01',
          isMandatory: false,
          downloadPath: '/api/apps/inventory/download',
        ),
        isInstalled: true,
        updateAvailable: true,
        status: 'ACTIVE',
        requiresExplicitAccess: false,
      ),
      CorporateApp(
        id: 'sales',
        name: 'Ventas PDA',
        packageName: 'com.company.sales',
        description: 'Pedidos, clientes y cierre de ventas en campo.',
        iconPath: '',
        installedVersion: null,
        installedVersionCode: null,
        latestVersion: const AppVersion(
          id: 'sales-2.0.0',
          versionName: '2.0.0',
          versionCode: 200,
          changelog: 'Nueva experiencia de toma de pedidos.',
          releaseDateIso: '2026-04-10',
          isMandatory: true,
          downloadPath: '/api/apps/sales/download',
        ),
        isInstalled: false,
        updateAvailable: false,
        status: 'ACTIVE',
        requiresExplicitAccess: false,
      ),
    ];
  }

  @override
  Future<CorporateApp> fetchAppById(String id, {String? deviceId}) async {
    final apps = await fetchApps(deviceId: deviceId);
    return apps.firstWhere((app) => app.id == id);
  }

  @override
  Future<AppVersion> fetchLatestVersion(String appId,
      {String? deviceId}) async {
    return (await fetchAppById(appId, deviceId: deviceId)).latestVersion!;
  }

  @override
  Future<void> deleteAppFromStore(String appId) async {}
}
