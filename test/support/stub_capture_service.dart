import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/capture.dart';
import 'package:personal_memory_os/core/services/capture_service.dart';

class StubCaptureService implements CaptureService {
  final List<Capture> _captures = _seedCaptures();

  @override
  Future<List<Capture>> fetchCaptures() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.from(_captures);
  }

  @override
  Future<Capture> uploadCapture({
    required File file,
    required CaptureType type,
    String? eventId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final now = DateTime.now();
    final capture = Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      eventId: eventId,
      type: type,
      storageKey: 'users/demo_user/${type.name}/${now.millisecondsSinceEpoch}',
      mimeType: type == CaptureType.photo ? 'image/jpeg' : 'audio/m4a',
      processingStatus: CaptureProcessingStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    _captures.insert(0, capture);
    // Simulate async AI processing
    Future.delayed(const Duration(seconds: 3), () {
      final i = _captures.indexWhere((c) => c.id == capture.id);
      if (i != -1) {
        _captures[i] = _captures[i].copyWith(
          processingStatus: CaptureProcessingStatus.processed,
          aiResult: CaptureAiResult(
            summary: 'AI processed ${type.name} content.',
            topics: ['AI', 'Cloud', 'AWS'],
            keyPoints: ['Key learning point from this capture'],
            actions: [],
          ),
        );
      }
    });
    return capture;
  }

  @override
  Future<Capture> saveTextNote({required String text, String? eventId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    final capture = Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      eventId: eventId,
      type: CaptureType.note,
      content: text,
      processingStatus: CaptureProcessingStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    _captures.insert(0, capture);
    return capture;
  }

  @override
  Future<Capture> saveLink({required String url, String? eventId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    final capture = Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      eventId: eventId,
      type: CaptureType.link,
      content: url,
      processingStatus: CaptureProcessingStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    _captures.insert(0, capture);
    return capture;
  }

  @override
  Future<Capture> retryProcessing(String id) async {
    final i = _captures.indexWhere((c) => c.id == id);
    if (i == -1) throw StateError('Capture not found');
    return _captures[i] = _captures[i].copyWith(processingStatus: CaptureProcessingStatus.queued);
  }

  @override
  Future<void> deleteCapture(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _captures.removeWhere((c) => c.id == id);
  }
}

List<Capture> _seedCaptures() {
  final now = DateTime.now();
  return [
    Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      type: CaptureType.photo,
      storageKey: 'users/demo_user/photos/slide_001.jpg',
      processingStatus: CaptureProcessingStatus.processed,
      aiResult: CaptureAiResult(
        summary: 'Presentation slide about Bedrock Agents architecture',
        topics: ['Bedrock Agents', 'Tool calling', 'AI workflows'],
        keyPoints: [
          'Agents can invoke tools to complete multi-step tasks',
          'Memory and context are maintained across invocations',
        ],
        actions: [
          ExtractedAction(
            title: 'Try building a Bedrock Agent prototype',
            sourceCaptureId: 'c1',
          ),
        ],
      ),
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now,
    ),
    Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      type: CaptureType.voice,
      duration: 127,
      transcription:
          'The speaker mentioned that RAG with Knowledge Bases gives grounded answers. I should build a prototype using Bedrock Knowledge Bases and test it with the hackathon project.',
      processingStatus: CaptureProcessingStatus.processed,
      aiResult: CaptureAiResult(
        summary: 'RAG with Amazon Bedrock Knowledge Bases for grounded AI answers',
        topics: ['RAG', 'Knowledge Bases', 'Bedrock'],
        actions: [
          ExtractedAction(
            title: 'Build RAG prototype with Bedrock Knowledge Bases',
            dueAt: now.add(const Duration(days: 14)),
          ),
        ],
      ),
      createdAt: now.subtract(const Duration(hours: 5)),
      updatedAt: now,
    ),
    Capture(
      id: const Uuid().v4(),
      userId: 'demo_user',
      type: CaptureType.note,
      content:
          'Key takeaways: 1. Use EventBridge Scheduler for reliable reminders. 2. Never depend on LLM to execute alarms. 3. Bedrock Guardrails for input validation.',
      processingStatus: CaptureProcessingStatus.processed,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now,
    ),
  ];
}
