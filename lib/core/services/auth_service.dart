import 'package:personal_memory_os/core/providers/auth_provider.dart';

/// A sign-in problem with a message safe to show the user.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Sign-in and sign-up. [StubAuthService] for offline demos; AppAuthService for
/// the real backend.
abstract class AuthService {
  Future<AppUser?> getCurrentUser();
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> signUp(String email, String password, String displayName);

  /// Sign in with an ID token from Google; the backend creates or links the account.
  Future<AppUser> signInWithGoogle(String idToken);
  Future<void> signOut();
}

/// Stub implementation — returns mock data in development.
class StubAuthService implements AuthService {
  AppUser? _currentUser;

  @override
  Future<AppUser?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _currentUser;
  }

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    await Future.delayed(const Duration(seconds: 1));
    _currentUser = AppUser(
      id: 'user_${email.hashCode.abs()}',
      email: email,
      displayName: email.split('@').first,
    );
    return _currentUser!;
  }

  @override
  Future<AppUser> signUp(
      String email, String password, String displayName) async {
    await Future.delayed(const Duration(seconds: 1));
    _currentUser = AppUser(
      id: 'user_${email.hashCode.abs()}',
      email: email,
      displayName: displayName,
    );
    return _currentUser!;
  }

  @override
  Future<AppUser> signInWithGoogle(String idToken) async {
    _currentUser = AppUser(id: 'google_${idToken.hashCode.abs()}', email: 'google.user@example.com', displayName: 'Google user');
    return _currentUser!;
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _currentUser = null;
  }
}
