import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/utils/reminder_plan.dart';

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

class StubEventService implements EventService {
  final List<Event> _events = _seedEvents();

  @override
  Future<List<Event>> fetchEvents() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.from(_events);
  }

  @override
  Future<Event> createEvent(Event event) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _events.add(event);
    return event;
  }

  Event _replace(Event updated) {
    final i = _events.indexWhere((e) => e.id == updated.id);
    if (i != -1) _events[i] = updated;
    return updated;
  }

  Event _find(String id) => _events.firstWhere((e) => e.id == id);

  @override
  Future<MilestoneChange> setRegistrationStatus(String eventId, RegistrationStatus status) async {
    final event = _find(eventId);
    final closing = status.stopsReminders;
    final deadlines = [
      for (final d in event.deadlines)
        closing && d.deadlineType == DeadlineType.registration && !d.isClosed
            ? d.withStatus(status == RegistrationStatus.registered
                ? 'completed'
                : status == RegistrationStatus.expired ? 'expired' : 'skipped')
            : d,
    ];
    return MilestoneChange(_replace(event.copyWith(registrationStatus: status, deadlines: deadlines)), 0);
  }

  Future<MilestoneChange> _close(String eventId, String deadlineId, String newStatus) async {
    final event = _find(eventId);
    if (!event.deadlines.any((d) => d.id == deadlineId)) throw StateError('Milestone not found');
    return MilestoneChange(
      _replace(event.copyWith(deadlines: [
        for (final d in event.deadlines) d.id == deadlineId ? d.withStatus(newStatus) : d,
      ])),
      0,
    );
  }

  @override
  Future<MilestoneChange> completeMilestone(String eventId, String deadlineId) =>
      _close(eventId, deadlineId, 'completed');

  @override
  Future<MilestoneChange> skipMilestone(String eventId, String deadlineId) =>
      _close(eventId, deadlineId, 'skipped');

  @override
  Future<List<PolicyReminder>> previewReminderPolicy(String eventId, ReminderPolicyChoice choice) async =>
      buildReminderPlan(_find(eventId), DateTime.now())
          .map((p) => PolicyReminder(title: p.title, at: p.at, isDeadline: p.isDeadline))
          .toList();

  @override
  Future<int> applyReminderPolicy(String eventId, ReminderPolicyChoice choice) async =>
      (await previewReminderPolicy(eventId, choice)).length;

  @override
  Future<Event> updateEvent(Event event) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i != -1) _events[i] = event;
    return event;
  }

  @override
  Future<void> deleteEvent(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _events.removeWhere((e) => e.id == id);
  }
}

List<Event> _seedEvents() {
  final now = DateTime.now();
  return [
    Event(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'AWS Hackathon 2026',
      description: 'Build an AI-powered solution using AWS services.',
      eventType: EventType.hackathon,
      startAt: now.add(const Duration(hours: 3)),
      endAt: now.add(const Duration(days: 2)),
      isVirtual: false,
      location: 'AWS Office, Bangalore',
      organizer: 'AWS User Group MDU',
      deadlines: [
        EventDeadline(
          id: const Uuid().v4(),
          eventId: '',
          userId: 'demo_user',
          title: 'Registration deadline',
          deadlineType: DeadlineType.registration,
          deadlineAt: now.add(const Duration(hours: 1)),
          createdAt: now,
        ),
      ],
      status: EventStatus.upcoming,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now,
      photoCount: 8,
      voiceNoteCount: 2,
    ),
    Event(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Gemini AI Workshop',
      eventType: EventType.workshop,
      startAt: now.subtract(const Duration(days: 6)),
      endAt: now.subtract(const Duration(days: 6))
          .add(const Duration(hours: 4)),
      isVirtual: false,
      location: 'Google Office',
      organizer: 'Google Developer Group',
      status: EventStatus.attended,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now,
      photoCount: 14,
      summaryId: 'summary_001',
    ),
    Event(
      id: const Uuid().v4(),
      userId: 'demo_user',
      title: 'Developer Meetup — AI Edition',
      eventType: EventType.meetup,
      startAt: now.subtract(const Duration(days: 18)),
      endAt: now.subtract(const Duration(days: 18))
          .add(const Duration(hours: 3)),
      isVirtual: false,
      location: 'TechHub Community Space',
      status: EventStatus.attended,
      createdAt: now.subtract(const Duration(days: 20)),
      updatedAt: now,
      voiceNoteCount: 3,
    ),
  ];
}
