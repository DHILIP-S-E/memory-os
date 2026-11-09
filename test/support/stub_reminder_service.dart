import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';

class StubReminderService implements ReminderService {
  final List<Reminder> _reminders = _seedReminders();

  @override
  Future<List<Reminder>> fetchReminders() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.from(_reminders);
  }

  @override
  Future<Reminder> createReminder(Reminder reminder) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final saved = reminder.copyWith(
      serverId: reminder.id,
      syncStatus: 'SYNCED',
    );
    _reminders.add(saved);
    return saved;
  }

  @override
  Future<Reminder> updateReminder(Reminder reminder) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index != -1) _reminders[index] = reminder;
    return reminder;
  }

  @override
  Future<void> deleteReminder(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _reminders.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> updateReminderStatus(String id, ReminderStatus status) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index != -1) {
      _reminders[index] = _reminders[index].copyWith(status: status);
    }
  }

  @override
  Future<void> snoozeReminder(String id, DateTime newTime) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index != -1) {
      _reminders[index] = _reminders[index].copyWith(
        scheduledAt: newTime,
        status: ReminderStatus.snoozed,
      );
    }
  }
}

List<Reminder> _seedReminders() {
  final now = DateTime.now();
  return [
    Reminder(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Submit AWS Hackathon application',
      description: 'Complete the team submission form',
      reminderType: ReminderType.deadline,
      scheduledAt: now.add(const Duration(hours: 2)),
      priority: ReminderPriority.high,
      alarmEnabled: true,
      offsets: [
        const ReminderOffset(offset: '-3d'),
        const ReminderOffset(offset: '-1d'),
        const ReminderOffset(offset: '-3h'),
      ],
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now,
      syncStatus: 'SYNCED',
    ),
    Reminder(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Gemini Workshop preparation',
      reminderType: ReminderType.time,
      scheduledAt: now.add(const Duration(hours: 5)),
      priority: ReminderPriority.medium,
      alarmEnabled: true,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now,
      syncStatus: 'SYNCED',
    ),
    Reminder(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Follow up with team on prototype',
      reminderType: ReminderType.followUp,
      scheduledAt: now.add(const Duration(days: 3)),
      priority: ReminderPriority.medium,
      createdAt: now.subtract(const Duration(hours: 6)),
      updatedAt: now,
      syncStatus: 'SYNCED',
    ),
    Reminder(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Check new hackathons',
      reminderType: ReminderType.recurring,
      scheduledAt: now.add(const Duration(days: 7)),
      priority: ReminderPriority.low,
      recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
      createdAt: now.subtract(const Duration(days: 7)),
      updatedAt: now,
      syncStatus: 'SYNCED',
    ),
  ];
}
