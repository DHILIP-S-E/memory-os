import 'dart:async';

import 'package:personal_memory_os/core/services/device_service.dart';
import 'package:personal_memory_os/core/services/push_token_source.dart';
import 'package:personal_memory_os/core/sync/sync_queue.dart';

/// Keeps the backend's knowledge of this device's push token up to date.
/// Registers once per distinct token; failures are retried on the next call
/// (the local alarm layer still fires meanwhile).
class PushRegistration {
  static const _lastTokenKey = 'push_token_registered_v1';

  final DeviceService _device;
  final PushTokenSource _source;
  final KeyValueStore _store;
  StreamSubscription<String>? _refresh;

  PushRegistration(this._device, this._source, this._store);

  /// Call after sign-in. Returns true if a registration request succeeded.
  Future<bool> register() async {
    final token = await _source.getToken();
    if (token == null || token.isEmpty) return false;
    return _send(token);
  }

  /// Re-register automatically when the platform rotates the token.
  void listenForRefresh() {
    _refresh ??= _source.onTokenRefresh.listen(_send);
  }

  Future<bool> _send(String token) async {
    if (await _store.read(_lastTokenKey) == token) return false;
    try {
      await _device.registerPushToken(token, platform: _source.platform);
      await _store.write(_lastTokenKey, token);
      return true;
    } catch (_) {
      return false; // retried on the next sign-in / refresh
    }
  }

  /// Call before signing out, while the session still works: this phone stops receiving the
  /// account's reminders, and the next sign-in registers again.
  Future<void> unregister() async {
    final token = await _store.read(_lastTokenKey);
    if (token == null || token.isEmpty) return;
    try {
      await _device.unregisterPushToken(token);
    } finally {
      await _store.write(_lastTokenKey, ''); // the next sign-in registers again
    }
  }

  Future<void> dispose() async => _refresh?.cancel();
}
