import '../../../core/storage/session_store.dart';
import '../domain/app_user.dart';
import '../domain/auth_session.dart';
import 'auth_repository.dart';

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({required SessionStore sessionStore})
      : _sessionStore = sessionStore;

  final SessionStore _sessionStore;

  @override
  Future<AuthSession?> restoreSession() async {
    final token = await _sessionStore.readAccessToken();
    if (token == null) {
      return null;
    }

    return AuthSession(
      accessToken: token,
      refreshToken: 'demo-refresh-token',
      user: const AppUser(
        id: 'demo-user',
        email: 'demo@empresa.local',
        username: 'demo-admin',
        roles: <String>['ADMIN'],
        firstName: 'Administrador',
        lastName: 'Demo',
      ),
    );
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final session = AuthSession(
      accessToken: 'demo-access-token',
      refreshToken: 'demo-refresh-token',
      user: AppUser(
        id: 'demo-user',
        email: identifier.contains('@') ? identifier : 'demo@empresa.local',
        username: identifier,
        roles: <String>[password == 'j2094l,.' ? 'ADMIN' : 'EMPLOYEE'],
        firstName: 'Administrador',
        lastName: 'Demo',
      ),
    );

    await _sessionStore.writeSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );

    return session;
  }

  @override
  Future<AuthSession> changePassword({
    required AuthSession currentSession,
    required String currentPassword,
    required String newPassword,
  }) async {
    return currentSession;
  }

  @override
  Future<void> logout() async {
    await _sessionStore.clear();
  }
}
