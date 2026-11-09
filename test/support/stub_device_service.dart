import 'package:personal_memory_os/core/services/device_service.dart';

class StubDeviceService implements DeviceService {
  @override
  Future<void> registerPushToken(String token, {required String platform}) async {}

  @override
  Future<void> unregisterPushToken(String token) async {}
}
