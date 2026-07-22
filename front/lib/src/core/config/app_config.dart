class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.useDemoData,
  });

  final Uri apiBaseUrl;
  final bool useDemoData;

  factory AppConfig.fromEnvironment() {
    const defaultUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:5201',
    );

    return AppConfig(
      apiBaseUrl: Uri.parse(defaultUrl),
      useDemoData: const bool.fromEnvironment(
        'USE_DEMO_DATA',
        defaultValue: false,
      ),
    );
  }
}
