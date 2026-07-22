import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_store.dart';
import '../data/auth_repository.dart';
import '../data/demo_auth_repository.dart';
import '../data/remote_auth_repository.dart';
import '../domain/auth_session.dart';

final appConfigProvider =
    Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

final sessionStoreProvider =
    Provider<SessionStore>((ref) => SharedPreferencesSessionStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    config: ref.watch(appConfigProvider),
    sessionStore: ref.watch(sessionStoreProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final sessionStore = ref.watch(sessionStoreProvider);
  final client = ref.watch(apiClientProvider).dio;

  if (config.useDemoData) {
    return DemoAuthRepository(sessionStore: sessionStore);
  }

  return RemoteAuthRepository(
    client: client,
    sessionStore: sessionStore,
  );
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(authRepositoryProvider).login(
            identifier: identifier,
            password: password,
          );
    });
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final currentSession = state.valueOrNull;

    if (currentSession == null) {
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(authRepositoryProvider).changePassword(
            currentSession: currentSession,
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
    });
  }
}
