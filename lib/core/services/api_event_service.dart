import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/services/event_service.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/api_mapper.dart';

/// Real implementation of [EventService] that calls the FastAPI backend.
class ApiEventService implements EventService {
  final ApiClient _client;

  ApiEventService(this._client);

  @override
  Future<List<Event>> fetchEvents() async {
    final data = await _client.get('/events') as List<dynamic>;
    return data.map((j) => eventFromApi(j)).toList();
  }

  @override
  Future<Event> createEvent(Event event) async {
    final data = await _client.post('/events', {
      'title': event.title,
      'description': event.description,
      'event_type': event.eventType.name,
      'start_at': event.startAt.toUtc().toIso8601String(),
      'end_at': event.endAt?.toUtc().toIso8601String(),
      'timezone': event.timezone,
      'location': event.location,
      'is_virtual': event.isVirtual,
      'event_url': event.eventUrl,
      'organizer': event.organizer,
      'registration_url': event.registrationUrl,
      'deadlines': event.deadlines.map((d) => {
        'title': d.title,
        'deadline_type': d.deadlineType.name,
        'deadline_at': d.deadlineAt.toUtc().toIso8601String(),
      }).toList(),
    });
    return eventFromApi(data);
  }

  @override
  Future<Event> updateEvent(Event event) async {
    final data = await _client.patch('/events/${event.id}', {
      'title': event.title,
      'description': event.description,
      'status': event.status.name,
      'start_at': event.startAt.toUtc().toIso8601String(),
      'end_at': event.endAt?.toUtc().toIso8601String(),
      'location': event.location,
      'event_url': event.eventUrl,
      'organizer': event.organizer,
    });
    return eventFromApi(data);
  }

  @override
  Future<void> deleteEvent(String id) async {
    await _client.delete('/events/$id');
  }

  /// Runs a milestone action, then reads the event back so the app shows exactly what the server holds.
  Future<MilestoneChange> _change(String eventId, Future<dynamic> Function() action) async {
    final result = await action() as Map<String, dynamic>;
    final stopped = (result['stopped_reminders'] as List<dynamic>? ?? const []).length;
    return MilestoneChange(eventFromApi(await _client.get('/events/$eventId')), stopped);
  }

  @override
  Future<MilestoneChange> setRegistrationStatus(String eventId, RegistrationStatus status) =>
      _change(eventId, () => _client.post('/events/$eventId/registration-status', {'status': status.apiValue}));

  @override
  Future<MilestoneChange> completeMilestone(String eventId, String deadlineId) =>
      _change(eventId, () => _client.post('/events/$eventId/deadlines/$deadlineId/complete', {}));

  @override
  Future<MilestoneChange> skipMilestone(String eventId, String deadlineId) =>
      _change(eventId, () => _client.post('/events/$eventId/deadlines/$deadlineId/skip', {}));

  @override
  Future<List<PolicyReminder>> previewReminderPolicy(String eventId, ReminderPolicyChoice choice) async {
    final query = Uri(queryParameters: choice.query).query;
    final data = await _client.get('/events/$eventId/reminder-policy${query.isEmpty ? '' : '?$query'}') as List<dynamic>;
    return data.map((raw) {
      final j = raw as Map<String, dynamic>;
      return PolicyReminder(
        title: j['title'] as String? ?? 'Reminder',
        at: DateTime.parse(j['scheduled_at'] as String).toLocal(),
        isDeadline: j['reminder_type'] == 'deadline',
        repeatsDaily: (j['recurrence_rule'] as String? ?? '').contains('FREQ=DAILY'),
      );
    }).toList();
  }

  @override
  Future<int> applyReminderPolicy(String eventId, ReminderPolicyChoice choice) async {
    final data = await _client.post('/events/$eventId/reminder-policy', choice.body) as List<dynamic>;
    return data.length;
  }
}
