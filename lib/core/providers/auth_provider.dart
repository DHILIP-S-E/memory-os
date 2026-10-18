import 'package:flutter/foundation.dart';
import 'package:personal_memory_os/core/services/google_token_source.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;

  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  /// How long to wait for the stored session before showing the login screen.
  final Duration sessionCheckTimeout;

  /// Google sign-in, when configured for this build.
  final GoogleTokenSource? _google;

  /// Runs just before signing out, while the session is still valid (for example to stop this
  /// phone receiving the account's push notifications). Failures never block signing out.
  final Future<void> Function()? onSigningOut;

  AuthProvider(this._authService,
      {this.sessionCheckTimeout = const Duration(seconds: 8), GoogleTokenSource? google, this.onSigningOut})
      : _google = google;

  bool get canUseGoogle => _google != null;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  String? _error;
  AuthStatus get status => _status;
  AppUser? get user => _user;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String? get error => _error;

  Future<void> checkAuthState() async {
    try {
      // A stuck session lookup (e.g. secure storage) must never leave the app on a
      // loading screen forever: after the limit, treat it as signed out.
      final user = await _authService.getCurrentUser().timeout(sessionCheckTimeout);
      if (user != null) {
        _user = user;
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> signInWithEmail(String email, String password) async {
    try {
      _error = null;
      _user = await _authService.signInWithEmail(email, password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp(String email, String password, String displayName) async {
    try {
      _error = null;
      _user = await _authService.signUp(email, password, displayName);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Google. Returns false, with no error, if the user closed the Google sheet.
  Future<bool> signInWithGoogle() async {
    final google = _google;
    if (google == null) return false;
    try {
      _error = null;
      final token = await google.idToken();
      if (token == null) return false;
      _user = await _authService.signInWithGoogle(token);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await onSigningOut?.call().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Never let a cleanup step stop someone signing out.
    }
    try {
      await _google?.signOut();
    } catch (_) {}
    await _authService.signOut();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
