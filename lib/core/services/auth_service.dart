import 'package:personal_memory_os/core/providers/auth_provider.dart';

/// A sign-in problem with a message safe to show the user.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Sign-in and sign-up. The app uses AppAuthService (email and Google, JWT
/// issued by the FastAPI backend).
abstract class AuthService {
  Future<AppUser?> getCurrentUser();
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> signUp(String email, String password, String displayName);

  /// Sign in with an ID token from Google; the backend creates or links the account.
  Future<AppUser> signInWithGoogle(String idToken);
  Future<void> signOut();
}
