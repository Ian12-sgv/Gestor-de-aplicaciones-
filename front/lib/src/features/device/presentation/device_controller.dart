import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/device_repository.dart';
import '../domain/device_profile.dart';

final _localDeviceRepositoryProvider = Provider<LocalDeviceRepository>((ref) {
  return LocalDeviceRepository();
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final config = ref.watch(appConfigProvider);

  if (config.useDemoData) {
    return ref.watch(_localDeviceRepositoryProvider);
  }

  return RemoteDeviceRepository(
    client: ref.watch(apiClientProvider).dio,
    localRepository: ref.watch(_localDeviceRepositoryProvider),
  );
});

final deviceProfileProvider = FutureProvider<DeviceProfile>((ref) {
  return ref.watch(deviceRepositoryProvider).getOrCreateProfile();
});

final registeredDeviceProfileProvider =
    FutureProvider<DeviceProfile>((ref) async {
  final repository = ref.watch(deviceRepositoryProvider);
  final profile = await repository.getOrCreateProfile();

  if (profile.isRegistered) {
    return profile;
  }

  return repository.registerDevice(profile);
});
