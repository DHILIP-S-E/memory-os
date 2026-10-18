import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:personal_memory_os/core/config.dart';
import 'package:personal_memory_os/core/services/push_token_source.dart';

/// This phone's Firebase Cloud Messaging token, so the server can push reminders to it.
///
/// Firebase is set up from build settings (see AppConfig), not a google-services.json file.
/// Any failure means "no token": the phone's own local alarms still ring.
class FirebasePushTokenSource implements PushTokenSource {
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: AppConfig.firebaseApiKey,
              appId: AppConfig.firebaseAppId,
              messagingSenderId: AppConfig.firebaseSenderId,
              projectId: AppConfig.firebaseProjectId,
            ),
          );
        }
        await FirebaseMessaging.instance.requestPermission();
      }();

  @override
  String get platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<String?> getToken() async {
    try {
      await _init();
      // The registration token is what the server's FCM v1 send call targets (message.token).
      // The newer register()/onRegistered API yields an installation ID instead, which the
      // server does not send to yet, so the token API stays until both move together.
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Push token unavailable: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => Stream.fromFuture(_init())
      // ignore: deprecated_member_use
      .asyncExpand((_) => FirebaseMessaging.instance.onTokenRefresh)
      .handleError((Object e) => debugPrint('Push token refresh failed: $e'));
}
