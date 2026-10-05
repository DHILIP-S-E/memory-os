# Design: Personal Memory OS

## Architecture Overview

```
Flutter App (dark Material 3)
  │
  │  Cognito JWT on every request
  ▼
AWS Amplify ──► AWS AppSync (GraphQL + Subscriptions)
                    │
                    ▼
            AWS Lambda (domain functions)
            ┌───────┬──────────┬────────────┬──────────────┐
            ▼       ▼          ▼            ▼              ▼
        Aurora   Amazon S3  EventBridge  Amazon SQS   Amazon SNS
       PostgreSQL (private) Scheduler   (async jobs)  (push notif)
      (source of   (KMS)      │              │            │
        truth)      │         ▼              ▼            ▼
                    │    Lambda          Lambda       APNs / FCM
                    │    dispatcher      workers
                    │                       │
                    ▼                       ▼
             Bedrock Data            Amazon Bedrock
             Automation              (Nova / Titan)
                    │                       │
                    └───────────┬───────────┘
                                ▼
                     Bedrock Knowledge Bases
                                │
                                ▼
                      OpenSearch Serverless
```

## Key Design Decisions

### 1. AI Never Executes Scheduling
Bedrock parses user intent and extracts structured data (dates, priorities, recurrence rules). Lambda then schedules the resulting job via EventBridge Scheduler. The LLM is never in the critical path of alarm delivery.

### 2. Two-Layer Alarm Reliability
Every critical reminder registers two independent delivery mechanisms:
- **Cloud layer:** EventBridge Scheduler → Lambda dispatcher → SNS → APNs/FCM
- **Device layer:** `flutter_local_notifications` scheduled on-device at creation time

If the device is offline, the cloud layer fires. If the cloud push fails, the local notification fires. Neither layer depends on the other.

### 3. Async Capture Processing
Upload completes instantly. AI processing (OCR, transcription, summarization, indexing) runs asynchronously via SQS queue. The Flutter client polls for status changes via AppSync subscriptions — the user is never blocked on an upload screen.

### 4. Source-Grounded AI Answers
Every response from the AI Chat feature must cite the originating memory documents (Bedrock Knowledge Base retrieval). Answers without source citations are rejected at the Lambda layer before being returned to the client.

### 5. User Confirmation Gate for AI Suggestions
No reminder, deadline, or action item created by AI is persisted without explicit user confirmation. The UI surfaces a confirmation card; Lambda writes the record only after the user taps "Save."

### 6. Capture-First UX
The capture flow is three taps maximum. AI organization is invisible to the user at capture time and surfaces later as enriched memory.

---

## Flutter App Structure

```
lib/
├── core/
│   ├── providers/          # ChangeNotifier providers
│   ├── services/           # Abstract service interfaces + implementations
│   ├── models/             # Data models (Reminder, Event, Capture, MemoryDocument, AiMessage)
│   └── theme/              # AppColors, AppTextStyles
├── features/
│   ├── today/              # Today screen (NowCard, reminders, events, memory)
│   ├── reminders/          # Reminder list, creation, detail
│   ├── events/             # Event list, creation, detail
│   ├── capture/            # Camera, voice, text, document, link capture
│   ├── memory/             # Memory timeline, search, AI chat
│   ├── auth/               # Sign-in, sign-up (Cognito)
│   └── settings/           # Profile, notifications, AI, storage, privacy
└── shared/
    └── widgets/            # Cross-feature reusable widgets
```

## AWS Lambda Domain Functions

| Function | Responsibility |
|---|---|
| `reminder-create` | Validate, write Aurora, schedule EventBridge + return device payload |
| `reminder-update` | Update Aurora, reschedule EventBridge if time changed |
| `reminder-delete` | Delete Aurora record, cancel EventBridge schedule |
| `reminder-process` | Dispatcher: receives EventBridge trigger, calls SNS |
| `event-create` | Validate, write Aurora, apply smart reminder policy |
| `event-update` | Update Aurora, reconcile reminder plan |
| `event-delete` | Delete Aurora, cancel associated schedules |
| `capture-create` | Generate pre-signed S3 URL, write capture record |
| `capture-process` | SQS consumer: BDA → Transcribe → Bedrock LLM → Aurora |
| `summary-generate` | On-demand memory document regeneration |
| `action-extract` | Extract action items from memory documents |
| `memory-index` | Sync Aurora memory documents to Knowledge Base |
| `memory-search` | Semantic + keyword hybrid search via Knowledge Base |
| `notification-dispatch` | EventBridge target: send SNS push, record delivery |
| `notification-status` | APNs/FCM delivery receipt webhook handler |

## Data Models

### Reminder
```dart
class Reminder {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime scheduledAt;
  final ReminderType type;           // time | deadline | recurring | followUp | multiStage
  final ReminderPriority priority;   // low | medium | high | critical
  final ReminderStatus status;       // active | snoozed | completed | overdue | cancelled
  final String? rrule;               // RFC 5545 for recurring
  final List<Duration>? stageOffsets; // for multi-stage
  final String? eventId;
  final String? eventBridgeScheduleArn;
  final bool localNotificationScheduled;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### Event
```dart
class Event {
  final String id;
  final String userId;
  final String name;
  final EventType type;
  final DateTime startDate;
  final DateTime? endDate;
  final String? location;
  final String? url;
  final String? organizer;
  final List<EventDeadline> deadlines;
  final EventStatus status;
  final String? memoryDocumentId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### Capture
```dart
class Capture {
  final String id;
  final String userId;
  final String? eventId;
  final CaptureType type;            // photo | voice | text | document | link
  final String? s3Key;
  final String? localPath;
  final CaptureStatus status;        // uploaded | queued | processing | processed | failed
  final String? transcript;
  final String? summary;
  final List<String> topics;
  final List<String> actionItems;
  final DateTime capturedAt;
}
```

## S3 Key Structure

```
personal-memory/
  users/{userId}/
    events/{eventId}/
      photos/
      audio/
      videos/
      documents/
      transcripts/
      generated/      ← AI summaries, extracted content
```

## GraphQL Schema (key types)

```graphql
type Reminder @model @auth(rules: [{allow: owner}]) {
  id: ID!
  title: String!
  scheduledAt: AWSDateTime!
  type: ReminderType!
  priority: ReminderPriority!
  status: ReminderStatus!
  rrule: String
  eventId: ID
}

type Capture @model @auth(rules: [{allow: owner}]) {
  id: ID!
  type: CaptureType!
  s3Key: String
  status: CaptureStatus!
  summary: String
  topics: [String]
  eventId: ID
}

type Subscription {
  onCaptureUpdated(userId: ID!): Capture
  @aws_subscribe(mutations: ["updateCapture"])
}
```

## Security Controls

| Layer | Control |
|---|---|
| API | Cognito JWT on every AppSync call |
| Lambda | User-level authorization (userId from JWT claim) |
| S3 | Private bucket + pre-signed URLs (15-min TTL) |
| Aurora | KMS encryption at rest, VPC-only access |
| S3 | KMS SSE-S3 encryption |
| AppSync | AWS WAF with rate limiting + IP reputation rules |
| Secrets | AWS Secrets Manager (DB credentials, API keys) |
| Audit | CloudTrail for all API calls |

## Bedrock Model Routing

| Use Case | Model |
|---|---|
| Natural language reminder parsing | Amazon Nova Lite |
| Text extraction / classification | Amazon Titan Text Lite |
| Event metadata extraction | Amazon Nova Lite |
| Capture summarization | Amazon Nova Lite |
| Cross-event synthesis | Amazon Nova Pro |
| Grounded Q&A (RAG) | Amazon Nova Pro |

Model IDs are stored in AWS Secrets Manager / environment variables — never hard-coded.
