import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_repository.dart';
import '../domain/device_profile.dart';

final _localDeviceRepositoryProvider = Provider<LocalDeviceRepository>((ref) {
  return LocalDeviceRepository();
});

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return ref.watch(_localDeviceRepositoryProvider);
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
