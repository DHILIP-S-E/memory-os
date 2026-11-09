import 'dart:convert';

import 'package:personal_memory_os/core/models/account_settings.dart';
import 'package:personal_memory_os/core/models/notification_delivery.dart';
import 'package:personal_memory_os/core/services/api_client.dart';

/// Data rights (spec R5.7, R5.8) and the account's own settings.
abstract class AccountService {
  /// Pretty-printed JSON of all the user's data.
  Future<String> exportData();

  /// Permanently deletes all user data (stored media, schedules, database rows).
  Future<void> deleteAllData();

  /// Timezone and quiet hours.
  Future<AccountSettings> getSettings();

  /// Changes only the fields given.
  Future<AccountSettings> updateSettings({
    String? timezone,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  });

  /// Every delivery attempt for this user's reminders, newest first.
  Future<List<NotificationDelivery>> notificationHistory({int limit = 50, int offset = 0});
}

class ApiAccountService implements AccountService {
  final ApiClient _client;

  ApiAccountService(this._client);

  @override
  Future<String> exportData() async {
    final data = await _client.get('/account/export');
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  @override
  Future<void> deleteAllData() async {
    await _client.delete('/account');
  }

  @override
  Future<AccountSettings> getSettings() async =>
      AccountSettings.fromJson(Map<String, dynamic>.from(await _client.get('/account/settings') as Map));

  @override
  Future<AccountSettings> updateSettings({
    String? timezone,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) async {
    final data = await _client.put('/account/settings', {
      if (timezone != null) 'timezone': timezone,
      if (quietHoursEnabled != null) 'quiet_hours_enabled': quietHoursEnabled,
      if (quietHoursStart != null) 'quiet_hours_start': quietHoursStart,
      if (quietHoursEnd != null) 'quiet_hours_end': quietHoursEnd,
    });
    return AccountSettings.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<NotificationDelivery>> notificationHistory({int limit = 50, int offset = 0}) async {
    final data = await _client.get('/notifications/history?limit=$limit&offset=$offset') as Map;
    return (data['items'] as List<dynamic>)
        .map((j) => NotificationDelivery.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }
}
