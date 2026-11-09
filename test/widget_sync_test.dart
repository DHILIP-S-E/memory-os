import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/widget/home_widget_bridge.dart';
import 'package:personal_memory_os/core/widget/widget_snapshot.dart';
import 'package:personal_memory_os/core/widget/widget_sync.dart';
import 'support/stub_services.dart';

class RecordingBridge implements HomeWidgetBridge {
  final sent = <WidgetSnapshot>[];

  @override
  Future<void> update(WidgetSnapshot snapshot) async => sent.add(snapshot);

  @override
  Future<bool> requestPin() async => false;
}

class EmptyReminders extends StubReminderService {
  @override
  Future<List<Reminder>> fetchReminders() async => [];
}

Reminder reminder(String id, DateTime at) => Reminder(
      id: id,
      userId: 'u',
      title: id,
      reminderType: ReminderType.time,
      scheduledAt: at,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  final now = DateTime(2026, 10, 1, 12);

  test('pushes once after startup, then again only when something visible changes', () {
    fakeAsync((async) {
      final reminders = ReminderProvider(EmptyReminders());
      final events = EventProvider(StubEventService());
      final bridge = RecordingBridge();
      final sync = WidgetSync(reminders, events, bridge, now: () => now,
          debounce: const Duration(milliseconds: 100))
        ..start();

      async.elapse(const Duration(milliseconds: 150));
      async.flushMicrotasks();
      expect(bridge.sent.length, 1);
      expect(bridge.sent.single.isEmpty, isTrue);

      // nothing visible changed: no redraw
      sync.push();
      async.flushMicrotasks();
      expect(bridge.sent.length, 1);

      // a reminder due this afternoon appears
      reminders.createReminder(reminder('Standup', now.add(const Duration(hours: 2))));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(bridge.sent.length, 2);
      expect(bridge.sent.last.lines.single.title, 'Standup');
      sync.dispose();
    });
  });

  test('a burst of changes is batched into one update', () {
    fakeAsync((async) {
      final reminders = ReminderProvider(EmptyReminders());
      final events = EventProvider(StubEventService());
      final bridge = RecordingBridge();
      final sync = WidgetSync(reminders, events, bridge, now: () => now,
          debounce: const Duration(milliseconds: 200))
        ..start();
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      final before = bridge.sent.length;

      for (var i = 0; i < 5; i++) {
        reminders.createReminder(reminder('r$i', now.add(Duration(hours: i + 1))));
      }
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(bridge.sent.length - before, 1);
      expect(bridge.sent.last.lines.length, 4, reason: 'capped to the widget size');
      sync.dispose();
    });
  });

  test('after dispose, changes no longer reach the widget', () {
    fakeAsync((async) {
      final reminders = ReminderProvider(EmptyReminders());
      final events = EventProvider(StubEventService());
      final bridge = RecordingBridge();
      final sync = WidgetSync(reminders, events, bridge, now: () => now,
          debounce: const Duration(milliseconds: 100))
        ..start();
      async.elapse(const Duration(milliseconds: 150));
      async.flushMicrotasks();
      sync.dispose();
      final before = bridge.sent.length;
      reminders.createReminder(reminder('late', now.add(const Duration(hours: 1))));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(bridge.sent.length, before);
    });
  });
}
