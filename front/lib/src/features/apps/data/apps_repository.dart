import '../domain/app_version.dart';
import '../domain/corporate_app.dart';

abstract class AppsRepository {
  Future<List<CorporateApp>> fetchApps({String? deviceId});
  Future<CorporateApp> fetchAppById(String id, {String? deviceId});
  Future<AppVersion> fetchLatestVersion(String appId, {String? deviceId});
  Future<void> deleteAppFromStore(String appId);
}
