# Requirements: Personal Memory OS

## Overview

An AWS-native personal intelligence platform that turns reminders, events, photos, voice notes, documents, and experiences into actionable reminders and searchable personal memory.

**Primary Platform:** Flutter mobile (iOS + Android)  
**Cloud Strategy:** AWS-first / AWS-native  
**AI Platform:** Amazon Bedrock

---

## R1 — Reminder Engine

- **R1.1** Users can create reminders with a title, date/time, priority, and type (time, deadline, recurring, follow-up, multi-stage)
- **R1.2** Users can describe a reminder in natural language; the system extracts intent, date, and priority via Amazon Bedrock (server-side Lambda — never direct from client)
- **R1.3** Recurring reminders support RFC 5545 RRULE syntax (daily, weekly, custom)
- **R1.4** Multi-stage reminders generate multiple offset notifications (e.g. -7d, -3d, -1d, -3h, -30m, -10m)
- **R1.5** Every reminder schedules BOTH a cloud-side EventBridge Scheduler job AND a local device notification
- **R1.6** Users can snooze, complete, or delete a reminder
- **R1.7** The system tracks every notification delivery attempt (status: SCHEDULED → TRIGGERED → SENT → DELIVERED → FAILED)
- **R1.8** Overdue reminders surface prominently in the Today screen and Reminders screen
- **R1.9** AI-suggested reminders (extracted from voice notes, captures) require user confirmation before creation

## R2 — Event Context

- **R2.1** Users can create events with type, dates, location, organizer, URL, and registration/submission deadlines
- **R2.2** Users can paste event text or a URL; AI extracts event metadata (name, date, deadlines, location) via Bedrock
- **R2.3** Event types: hackathon, conference, workshop, webinar, meetup, meeting, appointment, deadline, custom
- **R2.4** Each event generates a smart reminder policy based on its type (registration deadline reminders + event-day reminders)
- **R2.5** Events have status: DRAFT → REGISTERED → UPCOMING → ACTIVE → ATTENDED → COMPLETED
- **R2.6** Event deadlines (registration, submission, payment) are tracked separately and surface in the Today screen

## R3 — Capture

- **R3.1** Users can capture photos (camera + gallery), voice recordings, text notes, documents, and links
- **R3.2** Capture is immediate — organization happens asynchronously via AI, not at capture time
- **R3.3** Captures are uploaded to a private S3 bucket under `users/{userId}/events/{eventId}/...`
- **R3.4** S3 upload triggers EventBridge → SQS → Lambda processing pipeline
- **R3.5** Photos are processed by Bedrock Data Automation to extract text, topics, and key points
- **R3.6** Voice notes are transcribed (Bedrock Data Automation / Transcribe) then summarized by Bedrock LLM
- **R3.7** Processing status is tracked: UPLOADED → QUEUED → PROCESSING → PROCESSED → FAILED
- **R3.8** Captures can be associated with an active event at capture time or linked later
- **R3.9** Offline captures are queued locally and uploaded when connectivity is restored

## R4 — Memory & AI Retrieval

- **R4.1** Every processed event generates a structured memory document (overview, topics, takeaways, people, resources, action items, deadlines)
- **R4.2** Memory documents are indexed into Bedrock Knowledge Bases (embeddings → OpenSearch Serverless)
- **R4.3** Users can search memory by keyword, semantic query, time range, event, or topic
- **R4.4** Users can ask natural language questions ("What did I learn about Bedrock Agents?")
- **R4.5** Every AI answer must cite source events/captures (grounded retrieval — no un-sourced answers)
- **R4.6** Cross-event summaries identify repeated concepts across multiple events
- **R4.7** AI-extracted action items surface as suggestions; user confirms before a reminder is created

## R5 — Authentication & Security

- **R5.1** Authentication via Amazon Cognito User Pools (email + Google OAuth)
- **R5.2** All API calls carry a Cognito JWT; Lambda enforces user-level authorization
- **R5.3** S3 objects are private; Flutter always uses pre-signed URLs
- **R5.4** Data encrypted at rest (KMS for S3 and Aurora) and in transit (TLS)
- **R5.5** No secrets in source code — AWS Secrets Manager for all credentials
- **R5.6** AWS WAF protects the AppSync endpoint
- **R5.7** Users can delete individual records or their entire account (cascading S3 + Aurora + Knowledge Base cleanup)
- **R5.8** Users can export all their data (JSON / ZIP)

## R6 — Offline & Sync

- **R6.1** App loads cached reminders and events when offline
- **R6.2** New reminders created offline are stored locally and synced on reconnect
- **R6.3** Captures created offline are queued and uploaded on reconnect
- **R6.4** Sync state: LOCAL_ONLY → SYNCING → SYNCED → CONFLICT → FAILED
- **R6.5** Cloud is the source of truth after successful sync

## R7 — Notifications

- **R7.1** Critical reminders use two-layer delivery: EventBridge Scheduler (cloud) + flutter_local_notifications (device)
- **R7.2** Notifications support actions: Snooze, Mark Complete, Open Event
- **R7.3** Quiet hours are respected (configurable, default 22:00–07:00)
- **R7.4** Every delivery attempt is recorded in `notification_deliveries` table
