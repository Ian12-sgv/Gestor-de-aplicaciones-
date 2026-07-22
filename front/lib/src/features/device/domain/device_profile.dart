class DeviceProfile {
  const DeviceProfile({
    required this.deviceIdentifier,
    required this.displayName,
    required this.platform,
    this.deviceId,
    this.osVersion,
    this.appVersionName,
  });

  final String deviceIdentifier;
  final String displayName;
  final String platform;
  final String? deviceId;
  final String? osVersion;
  final String? appVersionName;

  bool get isRegistered => deviceId != null && deviceId!.isNotEmpty;

  DeviceProfile copyWith({
    String? deviceId,
    String? displayName,
    String? platform,
    String? osVersion,
    String? appVersionName,
  }) {
    return DeviceProfile(
      deviceIdentifier: deviceIdentifier,
      displayName: displayName ?? this.displayName,
      platform: platform ?? this.platform,
      deviceId: deviceId ?? this.deviceId,
      osVersion: osVersion ?? this.osVersion,
      appVersionName: appVersionName ?? this.appVersionName,
    );
  }
}
