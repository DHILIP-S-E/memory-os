import 'package:personal_memory_os/core/models/ai_message.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/models/event.dart';

/// Natural language reminder parse result from the AI service.
class NlpReminderResult {
  final String title;
  final ReminderType type;
  final DateTime? scheduledAt;
  final ReminderPriority priority;
  final List<String> offsets;

  /// Things the user must confirm before creating (missing date, past date,
  /// assumed time, ...). Empty when the parse is unambiguous.
  final List<String> ambiguities;

  const NlpReminderResult({
    required this.title,
    required this.type,
    this.scheduledAt,
    required this.priority,
    required this.offsets,
    this.ambiguities = const [],
  });

  /// Copy with a user-chosen date/time; resolves the date-related ambiguities.
  NlpReminderResult withScheduledAt(DateTime value) => NlpReminderResult(
        title: title,
        type: type,
        scheduledAt: value,
        priority: priority,
        offsets: offsets,
      );
}

/// Event extraction result from the AI service.
class EventExtractionResult {
  final String title;
  final String? description;
  final EventType eventType;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? location;
  final String? eventUrl;
  final String? organizer;
  final bool? isVirtual;
  final DateTime? registrationDeadline;
  final DateTime? submissionDeadline;
  final String? registrationUrl;

  /// field name -> the exact words on the page that support it
  final Map<String, String> evidence;

  /// Fields the page did not state, so nothing was guessed for them.
  final List<String> missingFields;

  /// Fields whose time of day was not stated; the server filled in a default.
  final List<String> assumedTimes;

  /// Dates in the text that could be read two ways.
  final List<String> ambiguousDates;

  const EventExtractionResult({
    required this.title,
    this.description,
    required this.eventType,
    this.startAt,
    this.endAt,
    this.location,
    this.eventUrl,
    this.organizer,
    this.isVirtual,
    this.registrationDeadline,
    this.submissionDeadline,
    this.registrationUrl,
    this.evidence = const {},
    this.missingFields = const [],
    this.assumedTimes = const [],
    this.ambiguousDates = const [],
  });
}

/// Abstracts all AI interactions. Call the backend, never the model directly from the Flutter client.
abstract class AiService {
  /// Parse natural language into a structured reminder.
  /// Backend: Gemini → structured JSON → validate → return.
  Future<NlpReminderResult> parseNaturalLanguageReminder(String input);

  /// Extract event metadata from pasted text or URL content.
  Future<EventExtractionResult> extractEventFromText(String text);

  /// Answer a question grounded in the user's personal memory.
  /// Backend: memory search → Gemini → grounded answer.
  Future<AiAnswer> askMemoryQuestion(String question);
}
