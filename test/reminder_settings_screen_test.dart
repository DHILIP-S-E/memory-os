import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/account_settings.dart';
import 'package:personal_memory_os/core/models/notification_delivery.dart';
import 'package:personal_memory_os/core/services/account_service.dart';
import 'package:personal_memory_os/features/settings/notification_history_screen.dart';
import 'package:personal_memory_os/features/settings/reminder_settings_section.dart';
import 'support/stub_services.dart';

/// Fails the first [failures] calls to getSettings, then behaves normally.
class FlakyAccount extends StubAccountService {
  int failures;
  bool failUpdates = false;

  FlakyAccount({this.failures = 0});

  @override
  Future<AccountSettings> getSettings() async {
    if (failures > 0) {
      failures--;
      throw Exception('SocketException: Connection timed out');
    }
    return super.getSettings();
  }

  @override
  Future<AccountSettings> updateSettings({String? timezone, bool? quietHoursEnabled, int? quietHoursStart, int? quietHoursEnd}) {
    if (failUpdates) throw Exception('SocketException: Connection timed out');
    return super.updateSettings(
      timezone: timezone,
      quietHoursEnabled: quietHoursEnabled,
      quietHoursStart: quietHoursStart,
      quietHoursEnd: quietHoursEnd,
    );
  }
}

Future<void> pumpSection(WidgetTester tester, AccountService account, {Future<String?> Function()? tz}) async {
  await tester.pumpWidget(Provider<AccountService>.value(
    value: account,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReminderSettingsSection(timezoneSource: tz ?? () async => 'Asia/Kolkata'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpHistory(WidgetTester tester, AccountService account) async {
  await tester.pumpWidget(Provider<AccountService>.value(
    value: account,
    child: const MaterialApp(home: NotificationHistoryScreen()),
  ));
  await tester.pumpAndSettle();
}

NotificationDelivery delivery(String id, String status, {String? error, String title = 'Pay rent'}) => NotificationDelivery(
      id: id,
      reminderId: 'r-$id',
      reminderTitle: title,
      status: status,
      error: error,
      fireAt: DateTime(2026, 10, 5, 12),
    );

void main() {
  group('reminder settings', () {
    testWidgets('shows the saved time zone and quiet hours', (tester) async {
      final account = StubAccountService()..settings = const AccountSettings(timezone: 'Asia/Kolkata');
      await pumpSection(tester, account);
      expect(find.textContaining('Asia/Kolkata'), findsOneWidget);
      expect(find.textContaining('10 PM to 7 AM'), findsOneWidget);
      expect(find.text('Notification history'), findsOneWidget);
    });

    testWidgets('turning quiet hours off is saved and shown', (tester) async {
      final account = StubAccountService();
      await pumpSection(tester, account);
      await tester.tap(find.byKey(const ValueKey('quiet-switch')));
      await tester.pumpAndSettle();
      expect(account.settings.quietHoursEnabled, isFalse);
      expect(find.textContaining('Off'), findsOneWidget);
      expect(find.byKey(const ValueKey('quiet-window-tile')), findsNothing, reason: 'no hours to edit while off');
    });

    testWidgets("tapping the time zone uses the phone's", (tester) async {
      final account = StubAccountService();
      await pumpSection(tester, account);
      await tester.tap(find.byKey(const ValueKey('timezone-tile')));
      await tester.pumpAndSettle();
      expect(account.settings.timezone, 'Asia/Kolkata');
      expect(find.textContaining('Time zone set to Asia/Kolkata'), findsOneWidget);
    });

    testWidgets("a time zone the phone cannot report says so and changes nothing", (tester) async {
      final account = StubAccountService();
      await pumpSection(tester, account, tz: () async => null);
      await tester.tap(find.byKey(const ValueKey('timezone-tile')));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't read this phone's time zone"), findsOneWidget);
      expect(account.settings.timezone, 'UTC');
    });

    testWidgets('the hours dialog opens and can be cancelled', (tester) async {
      await pumpSection(tester, StubAccountService());
      await tester.tap(find.byKey(const ValueKey('quiet-window-tile')));
      await tester.pumpAndSettle();
      expect(find.text('Quiet hours'), findsWidgets);
      expect(find.textContaining('High-priority reminders still ring'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('High-priority'), findsNothing);
    });

    testWidgets('a failed load is a plain message with Retry, and Retry works', (tester) async {
      final account = FlakyAccount(failures: 1);
      await pumpSection(tester, account);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 PM to 7 AM'), findsOneWidget);
    });

    testWidgets('a failed change is explained and leaves the setting as it was', (tester) async {
      final account = FlakyAccount()..failUpdates = true;
      await pumpSection(tester, account);
      await tester.tap(find.byKey(const ValueKey('quiet-switch')));
      await tester.pumpAndSettle();
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      expect(find.textContaining('10 PM to 7 AM'), findsOneWidget, reason: 'still on');
    });
  });

  group('notification history', () {
    testWidgets('an empty history says what will appear', (tester) async {
      await pumpHistory(tester, StubAccountService());
      expect(find.text('No notifications yet'), findsOneWidget);
    });

    testWidgets('lists each attempt with an honest status and what it does not prove', (tester) async {
      final account = StubAccountService()
        ..history = [
          delivery('1', 'sent'),
          delivery('2', 'cancelled', error: 'quiet hours', title: 'Call mum'),
          delivery('3', 'failed', title: 'Submit'),
        ];
      await pumpHistory(tester, account);
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-1'))).data, 'Sent');
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-2'))).data, 'Held for quiet hours');
      expect(tester.widget<Text>(find.byKey(const ValueKey('status-3'))).data, 'Failed');
      expect(find.textContaining('does not prove it was shown'), findsWidgets);
      expect(find.text('Call mum'), findsOneWidget);
    });

    testWidgets('a failed load is a plain message with Retry', (tester) async {
      final account = _FailingHistory();
      await pumpHistory(tester, account);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      account.fail = false;
      account.history = [delivery('1', 'sent')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Pay rent'), findsOneWidget);
    });

    testWidgets('a full page offers Load more, which adds the next page', (tester) async {
      final account = StubAccountService()
        ..history = [for (var i = 0; i < 51; i++) delivery('$i', 'sent', title: 'Item $i')];
      await pumpHistory(tester, account);
      await tester.scrollUntilVisible(find.text('Load more'), 400, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Load more'), findsNothing, reason: 'the last page is shorter than a full page');
      await tester.scrollUntilVisible(find.text('Item 50'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('Item 50'), findsOneWidget);
    });
  });
}

class _FailingHistory extends StubAccountService {
  bool fail = true;

  @override
  Future<List<NotificationDelivery>> notificationHistory({int limit = 50, int offset = 0}) async {
    if (fail) throw Exception('SocketException: Connection timed out');
    return super.notificationHistory(limit: limit, offset: offset);
  }
}
