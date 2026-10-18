import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/models/account_settings.dart';
import 'package:personal_memory_os/core/models/notification_delivery.dart';
import 'package:personal_memory_os/core/services/account_service.dart';
import 'package:personal_memory_os/core/services/timezone_sync.dart';

class FailingAccount extends StubAccountService {
  @override
  Future<AccountSettings> getSettings() async => throw Exception('SocketException: timed out');
}

class CountingAccount extends StubAccountService {
  int updates = 0;

  @override
  Future<AccountSettings> updateSettings({
    String? timezone,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) {
    updates++;
    return super.updateSettings(timezone: timezone);
  }
}

void main() {
  group('AccountSettings', () {
    test('reads the server fields and fills in the defaults', () {
      expect(
        AccountSettings.fromJson({'timezone': 'Asia/Kolkata', 'quiet_hours_enabled': false, 'quiet_hours_start': 23, 'quiet_hours_end': 6}),
        const AccountSettings(timezone: 'Asia/Kolkata', quietHoursEnabled: false, quietHoursStart: 23, quietHoursEnd: 6),
      );
      expect(AccountSettings.fromJson({}), const AccountSettings());
    });

    test('hours read the way people say them', () {
      expect(AccountSettings.hourLabel(0), '12 AM');
      expect(AccountSettings.hourLabel(7), '7 AM');
      expect(AccountSettings.hourLabel(12), '12 PM');
      expect(AccountSettings.hourLabel(22), '10 PM');
      expect(const AccountSettings().quietHoursLabel, '10 PM to 7 AM');
      expect(const AccountSettings(quietHoursEnabled: false).quietHoursLabel, 'Off');
    });
  });

  group('NotificationDelivery', () {
    NotificationDelivery of(String status, {String? error}) =>
        NotificationDelivery.fromJson({'id': 'd', 'reminder_id': 'r', 'status': status, 'error': error});

    test('reads the server fields, including the reminder title and times', () {
      final d = NotificationDelivery.fromJson({
        'id': 'd1',
        'reminder_id': 'r1',
        'reminder_title': 'Pay rent',
        'status': 'sent',
        'fire_at': '2026-10-05T07:05:23+00:00',
        'created_at': '2026-10-05T07:05:43+00:00',
      });
      expect(d.reminderTitle, 'Pay rent');
      expect(d.fireAt!.toUtc(), DateTime.utc(2026, 10, 5, 7, 5, 23));
    });

    test('"sent" is described as accepted, never as shown', () {
      final d = of('sent');
      expect(d.statusLabel, 'Sent');
      expect(d.explanation, contains('does not prove it was shown'));
    });

    test('a quiet-hours skip is explained as such', () {
      final d = of('cancelled', error: 'quiet hours');
      expect(d.heldByQuietHours, isTrue);
      expect(d.statusLabel, 'Held for quiet hours');
      expect(d.explanation, contains('quiet hours'));
      expect(of('cancelled').heldByQuietHours, isFalse);
    });

    test('a reminder that could not be pushed says why, and that the local alarm still rings', () {
      expect(of('skipped', error: 'push not configured').statusLabel, 'Not sent');
      expect(of('skipped', error: 'push not configured').explanation, contains('not set up yet'));
      expect(of('skipped', error: 'no device registered').explanation, contains('No phone was registered'));
      expect(of('skipped').explanation, contains('own alarm still rings'));
    });

    test('a failure says so and never leaks the raw error', () {
      expect(of('failed', error: 'botocore.exceptions.ClientError: secret detail').explanation, isNot(contains('botocore')));
      expect(of('failed').statusLabel, 'Failed');
    });
  });

  group('syncDeviceTimezone', () {
    test('saves the phone timezone when the server has a different one', () async {
      final account = StubAccountService();
      final changed = await syncDeviceTimezone(account, source: () async => 'Asia/Kolkata');
      expect(changed!.timezone, 'Asia/Kolkata');
      expect((await account.getSettings()).timezone, 'Asia/Kolkata');
    });

    test('does nothing when they already match', () async {
      final account = CountingAccount();
      await account.updateSettings(timezone: 'Asia/Kolkata');
      account.updates = 0;
      expect(await syncDeviceTimezone(account, source: () async => 'Asia/Kolkata'), isNull);
      expect(account.updates, 0, reason: 'no needless request');
    });

    test('follows the user when they travel', () async {
      final account = StubAccountService();
      await syncDeviceTimezone(account, source: () async => 'Asia/Kolkata');
      await syncDeviceTimezone(account, source: () async => 'Europe/London');
      expect((await account.getSettings()).timezone, 'Europe/London');
    });

    test('ignores a timezone it cannot read or that is not a real region name', () async {
      for (final bad in [null, '', '  ', 'GMT+5', 'Unknown', 'Etc']) {
        final account = CountingAccount();
        expect(await syncDeviceTimezone(account, source: () async => bad), isNull, reason: '$bad');
        expect(account.updates, 0, reason: '$bad');
      }
    });

    test('never throws, even when the server cannot be reached', () async {
      expect(await syncDeviceTimezone(FailingAccount(), source: () async => 'Asia/Kolkata'), isNull);
      expect(await syncDeviceTimezone(StubAccountService(), source: () async => throw Exception('no plugin')), isNull);
    });
  });
}
