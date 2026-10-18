import 'package:google_sign_in/google_sign_in.dart';
import 'package:personal_memory_os/core/services/auth_service.dart';

/// Gets a Google ID token for this app. The backend checks it and signs the user in.
abstract class GoogleTokenSource {
  /// The ID token, or null when the user closed the Google sheet.
  Future<String?> idToken();

  /// Forget the Google account on this phone (called on sign-out).
  Future<void> signOut();
}

class PluginGoogleTokenSource implements GoogleTokenSource {
  final String serverClientId;
  Future<void>? _initialized;

  PluginGoogleTokenSource(this.serverClientId);

  Future<void> _init() => _initialized ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> idToken() async {
    await _init();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const AuthException('Google did not return a sign-in token. Please try again.');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const AuthException('Google sign-in failed. Please try again.');
    }
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
  }
}
