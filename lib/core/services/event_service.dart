import 'package:personal_memory_os/core/models/event.dart';

/// What the user chose for an event's reminders (spec 4.5): when to be reminded before each
/// deadline, and whether to be reminded every day until registered.
class ReminderPolicyChoice {
  /// The steps the server understands, in the order they are shown.
  static const steps = ['now', '7d', '3d', '1d', 'morning', '3h'];
  static const defaultCadence = ['3d', '1d', '3h'];

  final List<String> cadence;
  final bool dailyUntilRegistered;

  const ReminderPolicyChoice({this.cadence = defaultCadence, this.dailyUntilRegistered = false});

  ReminderPolicyChoice copyWith({List<String>? cadence, bool? dailyUntilRegistered}) => ReminderPolicyChoice(
        cadence: cadence ?? this.cadence,
        dailyUntilRegistered: dailyUntilRegistered ?? this.dailyUntilRegistered,
      );

  Map<String, String> get query => {
        if (cadence.isNotEmpty) 'cadence': cadence.join(','),
        if (dailyUntilRegistered) 'daily_until_registered': 'true',
      };

  Map<String, dynamic> get body => {'cadence': cadence, 'daily_until_registered': dailyUntilRegistered};

  @override
  bool operator ==(Object other) =>
      other is ReminderPolicyChoice &&
      other.dailyUntilRegistered == dailyUntilRegistered &&
      other.cadence.join(',') == cadence.join(',');

  @override
  int get hashCode => Object.hash(cadence.join(','), dailyUntilRegistered);
}

/// One reminder the policy would create.
class PolicyReminder {
  final String title;
  final DateTime at;
  final bool isDeadline;

  /// A daily reminder (until the day before the deadline).
  final bool repeatsDaily;

  const PolicyReminder({required this.title, required this.at, this.isDeadline = false, this.repeatsDaily = false});
}

/// The event after closing a milestone, and how many of its reminders were stopped with it.
class MilestoneChange {
  final Event event;
  final int stoppedReminders;

  const MilestoneChange(this.event, this.stoppedReminders);
}

abstract class EventService {
  Future<List<Event>> fetchEvents();
  Future<Event> createEvent(Event event);
  Future<Event> updateEvent(Event event);
  Future<void> deleteEvent(String id);

  /// Track registration. Finishing it (registered, skipped, not eligible, expired) stops the
  /// registration reminders only; reminders for other milestones keep running.
  Future<MilestoneChange> setRegistrationStatus(String eventId, RegistrationStatus status);

  /// Mark one milestone done or skipped. Only its own reminders stop.
  Future<MilestoneChange> completeMilestone(String eventId, String deadlineId);
  Future<MilestoneChange> skipMilestone(String eventId, String deadlineId);

  /// The reminders the server would create for this choice. Nothing is created.
  Future<List<PolicyReminder>> previewReminderPolicy(String eventId, ReminderPolicyChoice choice);

  /// Create them on the server (both alarm layers, tagged with their milestone so finishing a
  /// milestone stops them). Applying twice never duplicates. Returns how many were created.
  Future<int> applyReminderPolicy(String eventId, ReminderPolicyChoice choice);
}
