import 'package:personal_memory_os/core/services/api_client.dart';

/// Registers this device's push token with the backend so the server's half of the
/// two-layer alarm (the reminder worker, through Firebase Cloud Messaging) can reach it.
abstract class DeviceService {
  Future<void> registerPushToken(String token, {required String platform});

  /// Stop sending this account's reminders to this phone (on sign-out).
  Future<void> unregisterPushToken(String token);
}

class ApiDeviceService implements DeviceService {
  final ApiClient _client;

  ApiDeviceService(this._client);

  @override
  Future<void> registerPushToken(String token, {required String platform}) async {
    await _client.post('/devices', {'token': token, 'platform': platform});
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    await _client.post('/devices/unregister', {'token': token});
  }
}

class StubDeviceService implements DeviceService {
  @override
  Future<void> registerPushToken(String token, {required String platform}) async {}

  @override
  Future<void> unregisterPushToken(String token) async {}
}
