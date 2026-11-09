import 'package:personal_memory_os/core/models/reminder.dart';

/// Abstracts the backend's reminder API (FastAPI REST).
abstract class ReminderService {
  Future<List<Reminder>> fetchReminders();
  Future<Reminder> createReminder(Reminder reminder);
  Future<Reminder> updateReminder(Reminder reminder);
  Future<void> deleteReminder(String id);
  Future<void> updateReminderStatus(String id, ReminderStatus status);
  Future<void> snoozeReminder(String id, DateTime newTime);
}
