class AppVersion {
  const AppVersion({
    required this.id,
    required this.versionName,
    required this.versionCode,
    required this.changelog,
    required this.releaseDateIso,
    required this.isMandatory,
    required this.downloadPath,
    this.minSupportedVersionCode,
  });

  final String id;
  final String versionName;
  final int versionCode;
  final String changelog;
  final String releaseDateIso;
  final bool isMandatory;
  final String downloadPath;
  final int? minSupportedVersionCode;

  String get version => versionName;
  bool get mandatory => isMandatory;

  factory AppVersion.fromJson(
    Map<String, dynamic> json, {
    String? appId,
  }) {
    return AppVersion(
      id: json['id'] as String,
      versionName: (json['versionName'] as String?) ??
          (json['version'] as String? ?? ''),
      versionCode: _parseInt(json['versionCode']) ?? 0,
      changelog: json['changelog'] as String? ?? '',
      releaseDateIso: (json['releasedAt'] as String?) ??
          (json['releaseDate'] as String? ?? ''),
      isMandatory: (json['isMandatory'] as bool?) ??
          (json['mandatory'] as bool? ?? false),
      downloadPath: (json['downloadPath'] as String?) ??
          (json['downloadUrl'] as String?) ??
          (appId != null ? '/api/apps/$appId/download' : ''),
      minSupportedVersionCode: _parseInt(json['minSupportedVersionCode']),
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
