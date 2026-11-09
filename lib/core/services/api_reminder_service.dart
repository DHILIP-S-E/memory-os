import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/services/reminder_service.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/api_mapper.dart';

/// Real implementation of [ReminderService] that calls the FastAPI backend.
class ApiReminderService implements ReminderService {
  final ApiClient _client;

  ApiReminderService(this._client);

  @override
  Future<List<Reminder>> fetchReminders() async {
    final data = await _client.get('/reminders') as List<dynamic>;
    return data.map((j) => reminderFromApi(j)).toList();
  }

  @override
  Future<Reminder> createReminder(Reminder reminder) async {
    final data = await _client.post('/reminders', {
      'title': reminder.title,
      'description': reminder.description,
      'reminder_type': reminder.reminderType.name,
      'scheduled_at': reminder.scheduledAt?.toUtc().toIso8601String(),
      'timezone': reminder.timezone,
      'priority': reminder.priority.name,
      'alarm_enabled': reminder.alarmEnabled,
      'notification_enabled': reminder.notificationEnabled,
      'recurrence_rule': reminder.recurrenceRule,
      'source': reminder.source.name,
      'context_id': reminder.contextId,
      'depends_on_id': reminder.dependsOnId,
      'offsets': reminder.offsets.map((o) => o.offset).toList(),
    });
    return reminderFromApi(data);
  }

  @override
  Future<Reminder> updateReminder(Reminder reminder) async {
    final data = await _client.patch('/reminders/${reminder.id}', {
      'title': reminder.title,
      'description': reminder.description,
      'priority': reminder.priority.name,
      'alarm_enabled': reminder.alarmEnabled,
    });
    return reminderFromApi(data);
  }

  @override
  Future<void> updateReminderStatus(String id, ReminderStatus status) async {
    await _client.patch('/reminders/$id', {'status': status.name});
  }

  @override
  Future<void> snoozeReminder(String id, DateTime newTime) async {
    await _client.patch('/reminders/$id', {
      'status': ReminderStatus.snoozed.name,
      'scheduled_at': newTime.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> deleteReminder(String id) async {
    await _client.delete('/reminders/$id');
  }
}
