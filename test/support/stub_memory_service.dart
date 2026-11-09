import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/memory_document.dart';
import 'package:personal_memory_os/core/services/memory_service.dart';

class StubMemoryService implements MemoryService {
  final List<MemoryDocument> _docs = _seedDocs();

  @override
  Future<List<MemoryDocument>> fetchMemoryDocuments() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.from(_docs);
  }

  @override
  Future<List<MemoryDocument>> searchMemory(String query) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final q = query.toLowerCase();
    return _docs.where((d) {
      return (d.eventTitle?.toLowerCase().contains(q) == true) ||
          (d.overview?.toLowerCase().contains(q) == true) ||
          d.keyTopics.any((t) => t.toLowerCase().contains(q)) ||
          d.keyTakeaways.any((t) => t.toLowerCase().contains(q)) ||
          d.thingsLearned.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }
}

List<MemoryDocument> _seedDocs() {
  final now = DateTime.now();
  return [
    MemoryDocument(
      id: const Uuid().v4(),
      userId: 'demo_user',
      eventTitle: 'Gemini AI Workshop',
      overview:
          'Hands-on workshop covering Google Gemini API capabilities, multimodal inputs, and building AI-powered applications.',
      keyTopics: [
        'Gemini API',
        'Multimodal AI',
        'Prompt engineering',
        'AI application development',
      ],
      keyTakeaways: [
        'Gemini supports text, images, video, and audio in a single prompt',
        'Function calling enables structured AI outputs',
        'System prompts dramatically improve output quality',
      ],
      thingsLearned: [
        'How to implement multimodal prompts',
        'Grounding responses with search results',
        'Rate limits and pricing model',
      ],
      resources: [
        'https://ai.google.dev/docs',
        'Gemini API quickstart guide',
      ],
      actionItems: [
        const ActionItemRef(title: 'Try Gemini API with multimodal input'),
        const ActionItemRef(title: 'Compare Gemini with Bedrock models'),
      ],
      eventDate: now.subtract(const Duration(days: 6)),
      createdAt: now.subtract(const Duration(days: 6)),
      updatedAt: now,
    ),
    MemoryDocument(
      id: const Uuid().v4(),
      userId: 'demo_user',
      eventTitle: 'Developer Meetup — AI Edition',
      overview:
          'Community meetup focused on practical AI applications, RAG systems, and agent architectures.',
      keyTopics: [
        'RAG',
        'AI Agents',
        'Tool calling',
        'Vector databases',
        'LLM orchestration',
      ],
      keyTakeaways: [
        'RAG with semantic search dramatically reduces hallucinations',
        'Agent tool calling enables real-world integrations',
        'Multi-agent systems can solve complex workflows',
      ],
      thingsLearned: [
        'How to build a RAG pipeline with embeddings',
        'Tool calling patterns for agents',
        'Evaluation frameworks for AI output quality',
      ],
      actionItems: [
        const ActionItemRef(
            title: 'Build RAG prototype using Bedrock Knowledge Bases'),
        const ActionItemRef(
            title: 'Evaluate LLM output quality with test dataset'),
      ],
      eventDate: now.subtract(const Duration(days: 18)),
      createdAt: now.subtract(const Duration(days: 18)),
      updatedAt: now,
    ),
  ];
}
