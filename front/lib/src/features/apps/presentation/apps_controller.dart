import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

import '../../device/domain/device_profile.dart';
import '../../device/presentation/device_controller.dart';
import '../data/app_runtime_service.dart';
import '../data/apps_repository.dart';
import '../data/demo_apps_repository.dart';
import '../data/remote_apps_repository.dart';
import '../domain/corporate_app.dart';

final appsRepositoryProvider = Provider<AppsRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = ref.watch(apiClientProvider).dio;

  if (config.useDemoData) {
    return const DemoAppsRepository();
  }

  return RemoteAppsRepository(client: client);
});

final appsControllerProvider =
    AsyncNotifierProvider<AppsController, List<CorporateApp>>(
        AppsController.new);

final appDetailProvider =
    FutureProvider.family<CorporateApp, String>((ref, appId) async {
  final deviceProfile = await _resolveRegisteredDeviceProfile(ref);
  final app = await ref.watch(appsRepositoryProvider).fetchAppById(
        appId,
        deviceId: deviceProfile?.deviceId,
      );
  return ref.read(appRuntimeServiceProvider).enrichAndSyncApp(
        app,
        deviceProfile: deviceProfile,
      );
});

class AppsController extends AsyncNotifier<List<CorporateApp>> {
  @override
  Future<List<CorporateApp>> build() async {
    final deviceProfile = await _resolveRegisteredDeviceProfile(ref);
    final apps = await ref.read(appsRepositoryProvider).fetchApps(
          deviceId: deviceProfile?.deviceId,
        );
    return ref.read(appRuntimeServiceProvider).enrichAndSyncApps(
          apps,
          deviceProfile: deviceProfile,
        );
  }

  Future<void> refreshCatalog() async {
    // Keep showing the current catalog while refreshing (e.g. on every resume
    // after the Android installer closes) instead of flashing a spinner.
    state = const AsyncLoading<List<CorporateApp>>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final deviceProfile = await _resolveRegisteredDeviceProfile(ref);
      final apps = await ref.read(appsRepositoryProvider).fetchApps(
            deviceId: deviceProfile?.deviceId,
          );
      return ref.read(appRuntimeServiceProvider).enrichAndSyncApps(
            apps,
            deviceProfile: deviceProfile,
          );
    });
  }

  Future<void> deleteAppFromStore(String appId) async {
    await ref.read(appsRepositoryProvider).deleteAppFromStore(appId);
    await refreshCatalog();
  }
}

Future<DeviceProfile?> _resolveRegisteredDeviceProfile(Ref ref) async {
  try {
    return await ref.read(registeredDeviceProfileProvider.future);
  } catch (_) {
    return null;
  }
}
