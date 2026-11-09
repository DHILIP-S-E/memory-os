import 'package:personal_memory_os/core/models/ai_message.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:personal_memory_os/core/services/ai_service.dart';

/// In-memory AI answers for tests.
class StubAiService implements AiService {
  @override
  Future<NlpReminderResult> parseNaturalLanguageReminder(
      String input) async {
    await Future.delayed(const Duration(seconds: 1));
    final lower = input.toLowerCase();

    // Simple heuristic parsing for demo
    DateTime? scheduledAt;
    ReminderType type = ReminderType.time;
    List<String> offsets = [];
    ReminderPriority priority = ReminderPriority.medium;

    if (lower.contains('every') || lower.contains('weekly') ||
        lower.contains('daily') || lower.contains('monday')) {
      type = ReminderType.recurring;
      scheduledAt = _nextWeekday(DateTime.monday);
    } else if (lower.contains('deadline') || lower.contains('submit') ||
        lower.contains('by ') || lower.contains('before ')) {
      type = ReminderType.deadline;
      priority = ReminderPriority.high;
      offsets = ['-3d', '-1d', '-3h'];
      scheduledAt = DateTime.now().add(const Duration(days: 7));
    } else if (lower.contains('follow up') || lower.contains('after')) {
      type = ReminderType.followUp;
      scheduledAt = DateTime.now().add(const Duration(days: 3));
    } else if (lower.contains('tomorrow')) {
      scheduledAt = DateTime.now().add(const Duration(days: 1))
          .copyWith(hour: 9, minute: 0);
    } else if (lower.contains('minutes')) {
      final match = RegExp(r'(\d+)\s*minutes').firstMatch(lower);
      final mins = int.tryParse(match?.group(1) ?? '30') ?? 30;
      scheduledAt = DateTime.now().add(Duration(minutes: mins));
    } else {
      scheduledAt = DateTime.now().add(const Duration(hours: 2));
    }

    // Extract a clean title
    String title = input
        .replaceAll(
            RegExp(r'remind me|every|tomorrow|monday|by |before |after |at |to '),
            '')
        .trim();
    if (title.isEmpty) title = input;
    title = title[0].toUpperCase() + title.substring(1);

    return NlpReminderResult(
      title: title,
      type: type,
      scheduledAt: scheduledAt,
      priority: priority,
      offsets: offsets,
    );
  }

  @override
  Future<EventExtractionResult> extractEventFromText(String text) async {
    await Future.delayed(const Duration(seconds: 1));
    final lower = text.toLowerCase();

    EventType type = EventType.custom;
    if (lower.contains('hackathon')) type = EventType.hackathon;
    else if (lower.contains('workshop')) type = EventType.workshop;
    else if (lower.contains('conference')) type = EventType.conference;
    else if (lower.contains('webinar')) type = EventType.webinar;
    else if (lower.contains('meetup') || lower.contains('meet-up')) {
      type = EventType.meetup;
    }

    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return EventExtractionResult(
      title: lines.isNotEmpty ? lines.first.trim() : 'Event',
      eventType: type,
      startAt: DateTime.now().add(const Duration(days: 7)),
      registrationDeadline: DateTime.now().add(const Duration(days: 4)),
      eventUrl: urlMatch?.group(0),
      isVirtual: lower.contains('online') || lower.contains('virtual') ||
          lower.contains('zoom') || lower.contains('meet'),
    );
  }

  @override
  Future<AiAnswer> askMemoryQuestion(String question) async {
    await Future.delayed(const Duration(seconds: 2));

    final lower = question.toLowerCase();

    if (lower.contains('bedrock') || lower.contains('agent')) {
      return AiAnswer(
        answer:
            'You encountered Bedrock Agents in two events. In the Gemini AI Workshop, a speaker compared agent architectures. At the Developer Meetup, tool calling and multi-agent patterns were discussed in detail.',
        sources: [
          const AiMessageSource(
            eventTitle: 'Gemini AI Workshop',
            captureType: 'voice note',
            captureRef: '#2',
          ),
          const AiMessageSource(
            eventTitle: 'Developer Meetup — AI Edition',
            captureType: 'photo',
            captureRef: '#4',
          ),
        ],
      );
    }

    if (lower.contains('rag')) {
      return AiAnswer(
        answer:
            'RAG (Retrieval-Augmented Generation) came up in the Developer Meetup. Key points: RAG with semantic search reduces hallucinations, Bedrock Knowledge Bases provides a managed RAG solution with OpenSearch Serverless as the vector store.',
        sources: [
          const AiMessageSource(
            eventTitle: 'Developer Meetup — AI Edition',
            captureType: 'note',
            captureRef: '#1',
          ),
        ],
      );
    }

    return AiAnswer(
      answer:
          'Based on your captured memories, you have attended 3 events in the past month covering AI, AWS, and cloud development. Your most frequent topics were AI agents, RAG, and Amazon Bedrock. You have 2 open action items related to building prototypes.',
      sources: [
        const AiMessageSource(
          eventTitle: 'Gemini AI Workshop',
          captureType: 'summary',
        ),
        const AiMessageSource(
          eventTitle: 'Developer Meetup — AI Edition',
          captureType: 'summary',
        ),
      ],
    );
  }

  DateTime _nextWeekday(int weekday) {
    var date = DateTime.now().add(const Duration(days: 1));
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    return date.copyWith(hour: 9, minute: 0, second: 0);
  }
}
