import '../entities/auth_entity.dart';
import '../entities/auth_provider.dart';

abstract class LoginRepository {
  Future<AuthEntity> login(String email, String password);
  Future<AuthEntity> register(String email, String password, String fullName);
  Future<AuthEntity> guestLogin();
  Future<AuthEntity> refreshSession(String? refreshToken);
  Future<void> signInWithProvider(AuthProvider provider, {String? redirectTo});
  Future<void> requestPasswordReset(String email, {String? redirectTo});
  Future<void> updatePassword(String newPassword);
}
