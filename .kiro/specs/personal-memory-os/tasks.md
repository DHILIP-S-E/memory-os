# Tasks: Personal Memory OS

## Status Key
- [x] Completed
- [ ] Pending
- [~] Partially complete (noted inline)

---

## Phase 1 — Foundation

- [x] Scaffold Flutter project structure (feature-first under `lib/features/`)
- [x] App theme: dark Material 3, `AppColors`, `AppTextStyles`
- [x] Routing with `go_router`
- [x] Provider layer: `ChangeNotifier` providers under `lib/core/providers/`
- [x] `pubspec.yaml` with all dependencies pinned
- [x] Steering documents: `project-standards`, `aws-architecture`, `flutter-patterns`

## Phase 2 — Data Models & Service Layer

- [x] Data models: `Reminder`, `Event`, `Capture`, `MemoryDocument`, `AiMessage`
- [x] Abstract service interfaces under `lib/core/services/`
- [x] Stub service implementations for all domains
- [x] Real service implementations (FastAPI + Cognito API clients replace stubs)

## Phase 3 — Core Screens

- [x] Today screen — `NowCard`, upcoming reminders, events, recent memory
- [x] Reminders screen — filter bar (Today / Upcoming / Recurring / Deadlines / Overdue / Completed)
- [x] Reminder creation screen — manual form + natural language (AI parse via Bedrock)
- [x] Capture screen — camera, gallery, voice recorder, text note, link
- [x] Memory screen — event timeline grouped by month
- [x] Memory search screen — keyword + semantic
- [x] AI Chat screen — grounded Q&A with source citations
- [x] Event create screen — manual + paste/AI extract
- [x] Event detail screen — deadlines, captures, memory summary
- [x] Settings screen — profile, notifications, AI, storage, privacy, account
- [x] Auth screen — email/password + Google (Cognito)

## Phase 4 — AWS Infrastructure

- [x] AWS CDK infrastructure stacks under `infra/` — 11 stacks
- [x] CDK synth tested (no deploy errors)
- [x] AWS Amplify config stub (`amplify_config.dart`)
- [ ] **Deploy and verify CDK stacks against a real AWS account**

## Phase 5 — Notifications & Scheduling

- [x] Local notification scheduling (`flutter_local_notifications`)
- [x] Cloud reminder scheduling: EventBridge Scheduler → dispatcher Lambda → SNS (R1.5, R7)
- [x] Two-layer alarm verification: cloud push + device local notification
- [x] Notification delivery tracking (`notification_deliveries` table)
- [x] Push token registration plumbing (`PushRegistration` + `POST /devices`)
- [ ] **Plug in `firebase_messaging` (needs a Firebase project)**

## Phase 6 — Capture Pipeline

- [x] S3 upload with pre-signed URLs
- [x] EventBridge → SQS → Lambda processor pipeline
- [x] Bedrock Data Automation integration (photos, documents)
- [x] Voice transcription (BDA / Transcribe) + Bedrock LLM summarization
- [x] Capture status polling — "AI ready" badge without manual refresh
- [x] Offline capture queue — local → upload on reconnect (R6)

## Phase 7 — Memory & AI

- [x] Memory document generation from processed captures
- [x] Bedrock Knowledge Base sync (embeddings → OpenSearch Serverless)
- [x] Semantic retrieval with per-user metadata filter
- [x] Source-grounded AI answers (every response cites originating captures)
- [x] Cross-event synthesis (Nova Pro)
- [x] AI-extracted action items → user confirmation → reminder creation (R4.7, R1.9)
- [x] Memory → Action → Reminder: dated action items from captures, one-tap suggestions

## Phase 8 — Events & Smart Reminders

- [x] Smart reminder plan per event type with one-tap "create all"
- [x] On-device reminder policy mirrors backend policy
- [x] Event deadline tracking surfaced in Today screen

## Phase 9 — Auth & Security

- [x] Cognito email/password auth flow
- [ ] **Google sign-in via Cognito Hosted UI**
- [x] Bedrock Guardrails on all model invocations (CDK guardrail + applied in API and worker)

## Phase 10 — Offline & Sync

- [x] Offline cache for reminders and events (R6.1)
- [x] Sync queue with state machine: LOCAL_ONLY → SYNCING → SYNCED → CONFLICT → FAILED
- [x] Conflict resolution: cloud is source of truth after successful sync

## Phase 11 — Platform Extras

- [x] Android share-sheet capture for events
- [x] Clipboard capture
- [x] Android home-screen widget (daily brief, pinnable from Settings)
- [ ] **iOS share extension** (requires Xcode + Apple Developer account)
- [ ] **iOS widget** (requires Xcode + Apple Developer account)

## Phase 12 — Privacy & Data Portability

- [x] Account export — full data dump (JSON / ZIP) (R5.8)
- [x] Account delete — cascading cleanup (S3 + Aurora + Knowledge Base) (R5.7)

## Phase 13 — UX Polish

- [x] Conditional ("if not done by Friday") reminders
- [x] Daily brief on Today screen
- [x] User review step for ambiguous AI-parsed dates
- [x] Capture status polling so "AI ready" appears without manual refresh

---

## Remaining Work (open items)

| # | Task | Blocker |
|---|------|---------|
| 1 | Deploy CDK stacks to real AWS account | Needs AWS account + credentials |
| 2 | Plug in `firebase_messaging` | Needs a Firebase project |
| 3 | Google sign-in via Cognito Hosted UI | Depends on Firebase/Google Cloud OAuth setup |
| 4 | iOS share extension | Requires Xcode + Apple Developer account |
| 5 | iOS widget | Requires Xcode + Apple Developer account |
