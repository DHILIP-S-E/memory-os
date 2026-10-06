# AI Principles — Personal Memory OS

These rules are non-negotiable. They exist to keep the app reliable,
safe, and trustworthy. Every code change must comply.

---

## 1. AI interprets; AWS services execute

Amazon Bedrock (via Lambda) parses user intent and extracts structured data.
AWS services — EventBridge Scheduler, SNS, SQS, Aurora — execute the actions.

The LLM is **never** in the critical path of:
- Alarm/reminder delivery
- Data persistence
- Notification dispatch

---

## 2. Never call Bedrock from Flutter

All LLM calls happen server-side: `Lambda → Bedrock`.

```
✅  Flutter → AppSync/API Gateway → Lambda → Bedrock
❌  Flutter → Bedrock (direct SDK call)
❌  Flutter → any HTTP endpoint that calls Bedrock inline
```

No Bedrock SDK, no direct `InvokeModel` HTTP calls, no streaming Bedrock
responses from the Flutter client. Ever.

---

## 3. Two-layer alarm strategy — both layers always required

Every critical reminder must register **both**:

| Layer | Mechanism | Survives |
|---|---|---|
| Cloud | EventBridge Scheduler → Lambda → SNS → APNs/FCM | Device offline, app killed |
| Device | `flutter_local_notifications` | Push delivery failure, no internet |

Registering only one layer is a bug. The LLM never schedules either layer.

---

## 4. Always confirm AI-generated actions before saving

AI-suggested reminders, deadlines, and action items are **suggestions only**.
They are never written to Aurora or AppSync without explicit user confirmation.

```
AI extracts action item
  → surface confirmation card to user
  → user taps "Save"
  → Lambda writes record
```

Silent auto-save of AI output is forbidden.

---

## 5. Every AI answer must be traceable to stored memory

All responses from the AI Chat feature must cite the originating memory
documents (Bedrock Knowledge Base retrieval).

Lambda must attach `citations` (source event IDs / capture IDs) to every
Bedrock response before returning it to the client.

Answers without source citations are rejected at the Lambda layer.
Hallucinated or un-sourced answers must never reach the Flutter client.

---

## 6. Source-grounded retrieval pipeline

```
User question (Flutter)
  → Lambda (memory-search function)
  → Bedrock Knowledge Base (semantic search with per-user metadata filter)
  → Retrieved chunks + source IDs
  → Lambda builds prompt with retrieved context
  → Bedrock LLM generates grounded answer
  → Lambda attaches source citations
  → Response returned to Flutter
```

The per-user metadata filter on Knowledge Base queries is mandatory —
users must never see other users' memories.

---

## 7. Bedrock model routing

| Use Case | Model |
|---|---|
| Simple extraction / classification | Amazon Titan Text Lite |
| Summarization | Amazon Nova Lite |
| Cross-event synthesis | Amazon Nova Pro |
| Complex personal question + RAG | Amazon Nova Pro |

Model IDs come from environment variables or AWS Secrets Manager.
They are never hard-coded in Lambda source.

---

## 8. Bedrock Guardrails

All model invocations must apply the project's Bedrock Guardrail.
The guardrail ID is injected at runtime from environment variables.
Do not invoke `InvokeModel` or `InvokeModelWithResponseStream` without
attaching the guardrail configuration.

---

## 9. Async processing — never block on AI

Capture processing (OCR, transcription, summarization, indexing) always
runs asynchronously via SQS. The Flutter client receives an immediate
`UPLOADED` status and polls for updates via AppSync subscriptions.

The user is never blocked waiting for AI on an upload screen.

---

## 10. Dead-letter queues for all async AI jobs

Every SQS queue that feeds a Lambda AI worker has a configured DLQ.
Failed jobs land in the DLQ and are never silently dropped.
CloudWatch alarms on DLQ depth notify the team of processing failures.
