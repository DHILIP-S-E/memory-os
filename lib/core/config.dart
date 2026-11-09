/// Build-time configuration, set with --dart-define (nothing secret lives here).
///
///   flutter run \
///     --dart-define=BACKEND_URL=http://192.168.1.10:8080 \
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=<web OAuth client id> \
///     --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
///
/// Anything left out is simply switched off: no Google button, no push (local alarms still ring).
class AppConfig {
  /// The API; defaults to the deployed backend. For a local one use http://10.0.2.2:8080 on the
  /// Android emulator, or http://<pc ip>:8080 on a phone on the same Wi-Fi.
  static const backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'https://memory-os-zit9.onrender.com');

  /// Google sign-in: the *web* OAuth client ID. Android needs it as the "server client ID" to
  /// receive an ID token the backend can check. Empty = no "Continue with Google" button.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '1032006864678-hpmn25rbom7bf12c9j5egmf10j0aevrb.apps.googleusercontent.com');

  static bool get googleSignInEnabled => googleServerClientId.isNotEmpty;

  /// Firebase, for push notifications (from the Firebase console's app settings).
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get pushEnabled =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;
}
