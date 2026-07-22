import '../domain/auth_session.dart';

abstract class AuthRepository {
  Future<AuthSession?> restoreSession();
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });
  Future<AuthSession> changePassword({
    required AuthSession currentSession,
    required String currentPassword,
    required String newPassword,
  });
  Future<void> logout();
}
