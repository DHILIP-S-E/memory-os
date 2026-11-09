import 'dart:convert';
import 'package:personal_memory_os/core/models/account_settings.dart';
import 'package:personal_memory_os/core/models/notification_delivery.dart';
import 'package:personal_memory_os/core/services/account_service.dart';

class StubAccountService implements AccountService {
  AccountSettings settings = const AccountSettings();
  List<NotificationDelivery> history = [];

  @override
  Future<String> exportData() async =>
      const JsonEncoder.withIndent('  ').convert({'demo': true});

  @override
  Future<void> deleteAllData() async {}

  @override
  Future<AccountSettings> getSettings() async => settings;

  @override
  Future<AccountSettings> updateSettings({
    String? timezone,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) async =>
      settings = settings.copyWith(
        timezone: timezone,
        quietHoursEnabled: quietHoursEnabled,
        quietHoursStart: quietHoursStart,
        quietHoursEnd: quietHoursEnd,
      );

  @override
  Future<List<NotificationDelivery>> notificationHistory({int limit = 50, int offset = 0}) async =>
      history.skip(offset).take(limit).toList();
}
