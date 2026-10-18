/// Where the platform push token comes from (FCM on Android, APNs via FCM on iOS).
///
/// [FirebasePushTokenSource] is used when the Firebase build settings are given;
/// otherwise [NoPushTokenSource], and only the phone's local alarms ring.
abstract class PushTokenSource {
  /// 'android' or 'ios', as the backend's device registration expects.
  String get platform;

  /// Current token, or null if push is unavailable / permission denied.
  Future<String?> getToken();

  /// Emits whenever the platform rotates the token.
  Stream<String> get onTokenRefresh;
}

class NoPushTokenSource implements PushTokenSource {
  @override
  String get platform => 'fcm';

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}
