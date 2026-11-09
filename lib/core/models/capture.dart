enum CaptureType { photo, voice, note, document, video, link }

enum CaptureProcessingStatus {
  uploaded,
  queued,
  processing,
  processed,
  failed,
}

class Capture {
  final String id;
  final String userId;
  final String? eventId;
  final CaptureType type;
  final String? storageKey; // object storage key
  final String? mimeType;
  final int? duration; // seconds for audio/video
  final String? transcription;
  final String? content; // for notes and links
  final String? thumbnailKey;
  final CaptureProcessingStatus processingStatus;
  final CaptureAiResult? aiResult;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Capture({
    required this.id,
    required this.userId,
    this.eventId,
    required this.type,
    this.storageKey,
    this.mimeType,
    this.duration,
    this.transcription,
    this.content,
    this.thumbnailKey,
    this.processingStatus = CaptureProcessingStatus.uploaded,
    this.aiResult,
    required this.createdAt,
    required this.updatedAt,
  });

  Capture copyWith({
    String? id,
    String? userId,
    String? eventId,
    CaptureType? type,
    String? storageKey,
    String? mimeType,
    int? duration,
    String? transcription,
    String? content,
    String? thumbnailKey,
    CaptureProcessingStatus? processingStatus,
    CaptureAiResult? aiResult,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Capture(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      eventId: eventId ?? this.eventId,
      type: type ?? this.type,
      storageKey: storageKey ?? this.storageKey,
      mimeType: mimeType ?? this.mimeType,
      duration: duration ?? this.duration,
      transcription: transcription ?? this.transcription,
      content: content ?? this.content,
      thumbnailKey: thumbnailKey ?? this.thumbnailKey,
      processingStatus: processingStatus ?? this.processingStatus,
      aiResult: aiResult ?? this.aiResult,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'eventId': eventId,
        'type': type.name,
        'storageKey': storageKey,
        'mimeType': mimeType,
        'duration': duration,
        'transcription': transcription,
        'content': content,
        'thumbnailKey': thumbnailKey,
        'processingStatus': processingStatus.name,
        'aiResult': aiResult?.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Capture.fromJson(Map<String, dynamic> json) => Capture(
        id: json['id'],
        userId: json['userId'],
        eventId: json['eventId'],
        type: CaptureType.values.byName(json['type']),
        storageKey: json['storageKey'],
        mimeType: json['mimeType'],
        duration: json['duration'],
        transcription: json['transcription'],
        content: json['content'],
        thumbnailKey: json['thumbnailKey'],
        processingStatus: CaptureProcessingStatus.values
            .byName(json['processingStatus'] ?? 'uploaded'),
        aiResult: json['aiResult'] != null
            ? CaptureAiResult.fromJson(json['aiResult'])
            : null,
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
      );
}

class CaptureAiResult {
  final String? summary;
  final List<String> topics;
  final List<String> keyPoints;
  final List<String> resources;
  final List<ExtractedAction> actions;

  const CaptureAiResult({
    this.summary,
    this.topics = const [],
    this.keyPoints = const [],
    this.resources = const [],
    this.actions = const [],
  });

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'topics': topics,
        'keyPoints': keyPoints,
        'resources': resources,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory CaptureAiResult.fromJson(Map<String, dynamic> json) =>
      CaptureAiResult(
        summary: json['summary'],
        topics: List<String>.from(json['topics'] ?? []),
        keyPoints: List<String>.from(json['keyPoints'] ?? []),
        resources: List<String>.from(json['resources'] ?? []),
        actions: (json['actions'] as List<dynamic>? ?? [])
            .map((a) => ExtractedAction.fromJson(a))
            .toList(),
      );
}

class ExtractedAction {
  final String title;
  final DateTime? dueAt;
  final String? sourceCaptureId;
  bool reminderCreated;

  ExtractedAction({
    required this.title,
    this.dueAt,
    this.sourceCaptureId,
    this.reminderCreated = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'dueAt': dueAt?.toIso8601String(),
        'sourceCaptureId': sourceCaptureId,
        'reminderCreated': reminderCreated,
      };

  factory ExtractedAction.fromJson(Map<String, dynamic> json) =>
      ExtractedAction(
        title: json['title'],
        dueAt: json['dueAt'] != null ? DateTime.parse(json['dueAt']) : null,
        sourceCaptureId: json['sourceCaptureId'],
        reminderCreated: json['reminderCreated'] ?? false,
      );
}
