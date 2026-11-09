import 'package:personal_memory_os/core/models/ai_message.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';
import 'package:personal_memory_os/core/services/api_client.dart';
import 'package:personal_memory_os/core/services/api_mapper.dart';

/// Real implementation of [AiService] — calls the FastAPI backend, which calls Gemini.
/// The app never calls the model directly.
class ApiAiService implements AiService {
  final ApiClient _client;

  ApiAiService(this._client);

  @override
  Future<NlpReminderResult> parseNaturalLanguageReminder(String input) async {
    final data = await _client.post('/ai/parse-reminder', {
      'text': input,
      'timezone': DateTime.now().timeZoneName,
    }) as Map<String, dynamic>;

    // Map backend response to NlpReminderResult
    ReminderType type;
    try {
      type = ReminderType.values.byName(
        (data['type'] as String? ?? 'time').replaceAll('-', '_'),
      );
    } catch (_) {
      type = ReminderType.time;
    }

    ReminderPriority priority;
    try {
      priority = ReminderPriority.values.byName(data['priority'] as String? ?? 'medium');
    } catch (_) {
      priority = ReminderPriority.medium;
    }

    DateTime? scheduledAt;
    final scheduledStr = data['scheduled_at'] as String?;
    if (scheduledStr != null && scheduledStr.isNotEmpty) {
      try {
        scheduledAt = DateTime.parse(scheduledStr).toLocal();
      } catch (_) {}
    }

    final offsets = (data['offsets'] as List<dynamic>?)
        ?.map((o) => o.toString())
        .toList() ?? [];

    return NlpReminderResult(
      title: data['title'] as String? ?? input,
      type: type,
      scheduledAt: scheduledAt,
      priority: priority,
      offsets: offsets,
      ambiguities: (data['ambiguities'] as List<dynamic>? ?? [])
          .map((a) => (a as Map<String, dynamic>)['message'] as String)
          .toList(),
    );
  }

  static List<String> _strings(dynamic v) => v is List ? v.whereType<String>().toList() : const [];

  @override
  Future<EventExtractionResult> extractEventFromText(String text) async {
    final data = await _client.post('/ai/extract-event', {
      'text': text,
    }) as Map<String, dynamic>;

    EventType eventType;
    try {
      eventType = EventType.values.byName(data['event_type'] as String? ?? 'custom');
    } catch (_) {
      eventType = EventType.custom;
    }

    DateTime? _parseDate(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    return EventExtractionResult(
      title: data['title'] as String? ?? 'Event',
      description: data['description'] as String?,
      eventType: eventType,
      startAt: _parseDate(data['start_at'] as String?),
      endAt: _parseDate(data['end_at'] as String?),
      location: data['location'] as String?,
      eventUrl: data['event_url'] as String?,
      organizer: data['organizer'] as String?,
      isVirtual: data['is_virtual'] as bool? ?? false,
      registrationDeadline: _parseDate(data['registration_deadline'] as String?),
      submissionDeadline: _parseDate(data['submission_deadline'] as String?),
      registrationUrl: data['registration_url'] as String?,
      evidence: {
        for (final e in (data['evidence'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      missingFields: _strings(data['missing_fields']),
      assumedTimes: _strings(data['assumed_times']),
      ambiguousDates: _strings(data['ambiguous_dates']),
    );
  }

  @override
  Future<AiAnswer> askMemoryQuestion(String question) async {
    final data = await _client.post('/memory/ask', {
      'question': question,
    }) as Map<String, dynamic>;

    final sources = (data['sources'] as List<dynamic>? ?? [])
        .map((s) => aiSourceFromApi(s))
        .toList();

    return AiAnswer(
      answer: data['answer'] as String? ?? 'No answer found.',
      sources: sources,
    );
  }
}
