# Personal Reminder & Memory OS — Full Project Specification

Version: 2.0  
Category: Daily Life Enhancement  
Hackathon lane: Startups  
AI: Google Gemini through a separately deployed backend  
Database: Project-managed PostgreSQL  
Media storage: Cloudflare R2  
Background processing: Application workers and a durable scheduler  
Airflow: Not required

## 1. Product overview

Personal Reminder & Memory OS captures content the user chooses to share from a webpage, app, screenshot, image, PDF, voice note, or text. It extracts useful facts and actions, proposes events/tasks/milestones, and schedules reminders that remain active until the relevant task is completed, skipped, or expires.

**Core workflow:** Capture → Understand → Review → Save → Schedule → Notify → Track completion → Search memory.

This is a general personal assistant, not a hackathon-only tracker. It should support hackathons, conferences, workshops, courses, exams, job applications, appointments, bills, travel, personal tasks, documents, and general memories.

### Example
A user is viewing a hackathon page and taps the assistant's capture action. The system extracts the event name, registration link, registration deadline, submission deadline, event date, eligibility, and required actions when present. The user reviews the extracted details and confirms them. The app creates a milestone timeline and reminder policy. If registration remains incomplete, it sends configured reminders before the deadline. When the user marks registration complete, registration reminders stop—but a separate submission deadline remains active.

## 2. Platform limitations and capture strategy

Do not promise unrestricted access to every screen on every device.

### Android
- Share Sheet and shared text/URLs.
- Screenshot/image import.
- Home-screen shortcut, widget, or Quick Settings tile.
- Explicitly activated screen capture using supported Android APIs and required consent.
- Optional accessibility/overlay features only if policy-compliant, opt-in, clearly explained, and genuinely necessary. Never continuously collect screens in the background.

### iOS
- Share Sheet / Share Extension.
- Screenshot/image import and copy/paste.
- Widgets and supported Shortcuts/App Intents.
- Optional in-app browser.
- A normal iOS app cannot freely read arbitrary other apps' screens or place a universal floating button over every app.

### Website and desktop browser
- Browser extension that reads the active tab only after the user clicks its action and grants the required permissions.
- URL/text paste and upload fallbacks.
- Web dashboard for viewing and managing saved events, tasks, reminders, and memories.

Show users what content will be processed, request appropriate permissions, and keep capture user-triggered.

## 3. Users and use cases

Primary users:
- Students tracking exams, scholarships, classes, and applications.
- Developers tracking hackathons, conferences, and submission deadlines.
- Professionals tracking meetings, deliverables, and follow-ups.
- Individuals managing appointments, bills, travel, and personal commitments.

Key use cases:
1. Capture a page and extract an event.
2. Create recurring reminders for an incomplete registration.
3. Capture a poster and extract date, venue, and registration link.
4. Turn a voice note into tasks and reminders.
5. Save a document and later search or ask questions about it.
6. See today's agenda, upcoming deadlines, and overdue tasks.
7. Sync changes across devices.
8. Capture drafts offline and synchronize later.

## 4. Functional requirements

### 4.1 Capture
Support URL, selected page text, screenshot, image, PDF/document, audio, voice transcript, and manually entered text. Record the capture time, content type, source URL/title where available, user ID, processing state, and object reference.

### 4.2 Page understanding
Prefer structured webpage text and metadata when available; use OCR/vision for screenshots and posters. Gemini should return validated structured data, not free-form instructions.

Extract where available:
- Title/name, organizer, event type, and summary.
- Source URL and registration URL.
- Registration opening date and deadline.
- Event start/end date and time.
- Submission deadline, payment deadline, location, and online meeting details.
- Eligibility, required documents, preparation tasks, and contact details.
- Evidence snippets, confidence, and fields requiring confirmation.

Never invent missing dates. Return null for unknown values. Ask the user to clarify ambiguous dates or missing information needed to schedule a reminder.

### 4.3 Events and milestones
Use a general Event/Opportunity entity with types such as hackathon, conference, workshop, course, exam, job/internship, appointment, bill, travel, submission, personal task, and other.

An event can have independent milestones:
- Registration opens/deadline.
- Team formation deadline.
- Abstract/proposal deadline.
- Submission deadline.
- Payment deadline.
- Event start/end.
- Follow-up deadline.

Each milestone has its own date, status, reminder policy, and completion state.

### 4.4 Registration tracking
States: Not started, Planned, In progress, Registered, Waitlisted, Failed, Not eligible, Skipped, Expired.

- Default to Not started when registration is available but not confirmed.
- Let the user mark registration complete manually.
- Optionally attach a confirmation email, number, or screenshot.
- Do not claim automatic detection unless a supported, authorized integration provides reliable evidence.
- Stop registration reminders when status becomes Registered, Skipped, Not eligible, or Expired.
- Do not stop submission reminders when registration is completed.
- After the deadline, mark the milestone expired/overdue and stop repeated reminders by default. Let users configure any post-deadline follow-up explicitly.

### 4.5 Reminder policy engine
Reminder scheduling must be deterministic backend logic. Gemini may propose dates or policies, but it must not be the sole mechanism guaranteeing delivery.

Support:
- Fixed date/time reminders.
- Relative reminders before deadlines.
- Recurring daily/weekly/monthly reminders.
- Event preparation reminders.
- Repeated reminders until a defined completion/stop condition.
- User time zones, quiet hours, and preferred channels.
- Snooze, reschedule, complete, skip, and dismiss actions.
- Duplicate suppression, retries, and missed-job recovery.

Example editable registration cadence: immediately after saving, 7 days before, 3 days before, 1 day before, and on deadline morning. Daily reminders may be enabled while the deadline is still in the future and registration remains incomplete. If no deadline is known, ask the user rather than guessing.

Every repeating policy must have explicit stop conditions and a deadline/maximum duration. Do not create an unbounded reminder loop.

### 4.6 Notification delivery
Potential channels: Android local notifications, iOS local notifications, web push, email, and later optional SMS/messaging integration.

- Maintain canonical reminder state on the backend.
- Use local notifications for near-term/offline support where platform limits permit.
- Use a durable scheduler/worker for cloud-triggered delivery.
- Track scheduled, attempted, provider-accepted, failed, and retried states where available.
- Provider acceptance is not proof that a notification was displayed or read.
- Use idempotency keys and bounded exponential retry.
- Record permanent failures for diagnosis and provide notification history.
- The user's browser must not need to remain open for a cloud reminder to run.

### 4.7 Personal memory
Save notes, transcripts, images, documents, URLs, webpage summaries, event details, and task history. Support keyword and semantic search, source-linked answers, filters, edit/delete/export, and user correction. Store original source material separately from generated summaries. Enforce per-user isolation.

### 4.8 Dashboard
Show today's reminders, upcoming events/deadlines, pending registrations, overdue items, recent captures, preparation tasks, and quick capture. Prioritize actions and deadlines over a chat-only interface.

### 4.9 Media processing
- Store image/audio/document binaries in Cloudflare R2.
- Store metadata and references in PostgreSQL.
- Use short-lived signed URLs for private uploads/downloads.
- Validate file type, size, ownership, and allowed formats.
- Process OCR/transcription/document extraction asynchronously where useful.
- Keep R2 private by default; avoid public permanent URLs for private content.

### 4.10 Offline and sync
Allow local draft capture offline. Use client-generated IDs and idempotent sync to avoid duplicates. Resolve multi-device conflicts explicitly. Show sync status. Do not claim a reminder is cloud-scheduled until it has synced and been persisted; schedule local reminders only after date/time confirmation and permissions.

### 4.11 Authentication and settings
Use a trusted identity provider for Google sign-in and any needed email sign-in. Support account recovery/deletion, time zone, language, quiet hours, notification preferences, capture permissions, data export, and deletion.

## 5. Recommended architecture

```text
Android / iOS app     Browser extension     Web dashboard
        \                    |                    /
                    HTTPS REST API
                           |
                    FastAPI backend
              /            |             \
        Auth/RBAC       Capture API    Reminder/Memory API
              \            |             /
                      PostgreSQL
                           |
                 Durable job/outbox table
                           |
                 Scheduler + worker process
                 /           |             \
             Gemini       Cloudflare R2   Push/email provider
```

Recommended components:
- Mobile: Flutter if the current codebase does not already dictate another framework.
- Web dashboard: reuse the existing frontend framework.
- Browser extension: separate client using explicit active-tab permissions.
- Backend: Python FastAPI.
- Database: PostgreSQL as source of truth.
- ORM/migrations: SQLAlchemy and Alembic.
- AI: Gemini API, called only by the backend.
- Media: Cloudflare R2.
- Jobs: PostgreSQL-backed job/outbox pattern and worker for MVP. Redis or a managed queue can be added if actual throughput requires it.
- Scheduling: separate scheduler/worker process or dependable platform cron triggering a database-backed job runner.
- Notifications: FCM for Android/web push and APNs through an appropriate provider for iOS; email provider if required.
- Deployment: Docker containers on a VPS/container platform or cloud container service.
- Observability: structured logs, health checks, metrics, error reporting, and audit events.

### AWS is optional
Do not make AWS managed databases or object storage core dependencies. Keep PostgreSQL and Cloudflare R2 as selected. If useful, AWS may host containers, provide CloudWatch monitoring, Secrets Manager, SES email, or SQS for higher-volume async processing. Gemini remains the selected AI provider unless the team explicitly chooses otherwise. Do not duplicate services without a documented reason. No Airflow.

## 6. PostgreSQL data model

Use UUID primary keys, UTC timestamps for instants, and an IANA timezone per user/event/policy. Keep date-only deadlines separate from timed deadlines.

### `users`
`id`, `email`, `display_name`, `timezone`, `locale`, `created_at`, `updated_at`, `deleted_at`.

### `user_settings`
`user_id`, `quiet_hours_start`, `quiet_hours_end`, `default_notification_channels` JSONB, `default_reminder_policy` JSONB, `language`, `settings_json` JSONB.

### `captures`
`id`, `user_id`, `source_type`, `source_url`, `source_title`, `object_key`, `raw_text` where appropriate, `processing_status`, `captured_at`, `created_at`.

### `events`
`id`, `user_id`, `capture_id`, `title`, `summary`, `event_type`, `organizer`, `source_url`, `location_text`, `is_online`, `start_at`, `end_at`, `timezone`, `registration_url`, `registration_status`, `confidence_json` JSONB, timestamps, `archived_at`.

### `milestones`
`id`, `user_id`, `event_id`, `task_id`, `milestone_type`, `title`, `due_at`, `due_date`, `timezone`, `status`, `source_evidence` JSONB, timestamps, `completed_at`.

### `tasks`
`id`, `user_id`, `event_id`, `title`, `description`, `status`, `priority`, `due_at`, `timezone`, timestamps, `completed_at`.

### `reminder_policies`
`id`, `user_id`, `milestone_id`, `task_id`, `policy_json` JSONB, `active`, `stop_condition`, timestamps.

### `reminder_jobs`
`id`, `user_id`, `policy_id`, `due_at`, `status`, unique `idempotency_key`, `attempt_count`, `next_attempt_at`, `last_error`, timestamps.

### `notification_deliveries`
`id`, `user_id`, `reminder_job_id`, `channel`, `provider_message_id`, `status`, `attempted_at`, `accepted_at`, `failed_at`, `error_code`, `error_message`.

### `memories`
`id`, `user_id`, `capture_id`, `title`, `summary`, `content_text`, `content_type`, `source_url`, `object_key`, `tags` JSONB, timestamps, `deleted_at`.

### `extraction_runs`
`id`, `user_id`, `capture_id`, `provider`, `model`, `prompt_version`, `status`, `structured_output` JSONB, `validation_errors` JSONB, `created_at`, `completed_at`.

### `audit_events`
`id`, `user_id`, `actor_type`, `action`, `entity_type`, `entity_id`, `metadata` JSONB, `created_at`.

Index ownership/status/due-time fields. Use PostgreSQL full-text search first; add vector search only when the use case warrants it.

## 7. API outline

Base path: `/api/v1`.

Authentication (provider-dependent):
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /auth/me`
- `DELETE /auth/account`

Captures:
- `POST /captures`
- `POST /captures/{id}/upload-url`
- `POST /captures/{id}/process`
- `GET /captures/{id}`
- `GET /captures`
- `POST /captures/{id}/extract`
- `POST /captures/{id}/convert-to-event`

Events/milestones:
- `POST /events`, `GET /events`, `GET /events/{id}`, `PATCH /events/{id}`, `DELETE /events/{id}`
- `POST /events/{id}/milestones`
- `PATCH /milestones/{id}`
- `POST /milestones/{id}/complete`
- `POST /events/{id}/registration-status`

Tasks/reminders:
- `POST /tasks`, `GET /tasks`, `PATCH /tasks/{id}`, `POST /tasks/{id}/complete`
- `POST /reminder-policies`, `PATCH /reminder-policies/{id}`
- `POST /reminders/{id}/snooze`
- `POST /reminders/{id}/reschedule`
- `GET /reminders/upcoming`
- `GET /notifications/history`

Memory/dashboard/sync:
- `POST /memories`, `GET /memories`, `GET /memories/{id}`, `PATCH /memories/{id}`, `DELETE /memories/{id}`
- `POST /memory/search`, `POST /memory/ask`
- `GET /dashboard/today`, `GET /dashboard/upcoming`
- `POST /sync/push`, `GET /sync/changes?since=...`

All endpoints need ownership checks, validation, pagination, rate limits, consistent errors, request IDs, and idempotency for create/process/delivery operations.

## 8. Gemini integration

The Gemini key must never be placed in the mobile app, website, or browser extension. All model calls happen on the backend.

Processing workflow:
1. Receive user-authorized page content or file reference.
2. Sanitize and limit input.
3. Extract page text/metadata; use OCR/vision only when needed.
4. Ask Gemini for structured JSON against a versioned schema.
5. Parse and validate with Pydantic.
6. Normalize dates/timezones and flag low-confidence values.
7. Save the proposal with evidence.
8. Show the user a review/confirmation screen.
9. Create events, milestones, tasks, and reminder policies after confirmation.

Conceptual output:
```json
{
  "title": "Example Hackathon",
  "event_type": "hackathon",
  "source_url": "https://example.org/event",
  "registration_url": "https://example.org/register",
  "registration_deadline": {
    "value": "2026-11-05T23:59:00",
    "timezone": "Asia/Kolkata",
    "confidence": 0.91,
    "evidence": "Register by 5 November"
  },
  "event_start": null,
  "submission_deadline": null,
  "required_actions": ["Complete registration"],
  "missing_fields": ["event_start"],
  "needs_user_review": true
}
```
Illustrative only. Production output must be validated; unknown values stay null.

Treat webpage text, PDFs, OCR, and emails as untrusted input. Instructions embedded in those sources must never override system policy or trigger external actions. Do not allow extracted content to access secrets or call arbitrary tools. Do not infer a registration deadline from the event date. Keep date-only deadlines date-only. Ask about ambiguous dates such as `04/05/2027`.

## 9. Scheduling and delivery reliability

No Airflow is required. Use a small durable scheduler and worker:
- PostgreSQL stores reminder jobs and a transactional outbox.
- Scheduler discovers due jobs.
- Workers claim jobs atomically, for example using transactions and `FOR UPDATE SKIP LOCKED`.
- Every delivery has an idempotency key and an audit record.
- Retry transient errors with bounded exponential backoff.
- Reconcile overdue jobs after restarts.
- Use UTC for execution and the user's timezone for recurrence/display.
- Cancel future registration jobs when registration is completed, skipped, ineligible, or expired.
- Keep submission reminders independent.
- Respect quiet hours and suppress duplicates across channels.
- Monitor due-job backlog, job age, retries, and provider errors.

The user's browser must not remain open for reminders to execute. A scheduled job is not proof of notification delivery; record provider results and be precise about what is known.

## 10. Cloudflare R2 rules

- Private bucket by default.
- Short-lived signed upload/download URLs.
- Validate content type, file size, ownership, and extension.
- Use opaque object keys.
- Keep ownership and object metadata in PostgreSQL.
- Keep R2 credentials on the server with least-privilege access.
- Define retention/deletion behavior and temporary-upload cleanup.
- Back up PostgreSQL and document object recovery separately.
- Never use R2 as a substitute for relational reminder state.

## 11. Security and privacy

- TLS for all traffic.
- Secrets only in server-side environment/secret storage; never commit them.
- Enforce user ownership for every resource.
- Encrypt backups and private objects.
- Short-lived signed URLs and rate limits.
- Validate uploads and limit AI input/output sizes.
- Request consent before sending content to Gemini or external providers.
- Explain screen, browser, microphone, accessibility, and notification permissions.
- Never collect screen content continuously in the background.
- No plaintext passwords; use a trusted identity provider.
- Redact tokens and sensitive content from logs.
- Support export, deletion, retention rules, and account deletion.
- Keep audit events for important state changes.
- Treat AI output as untrusted until validated.

## 12. Required UI

### Mobile
1. Onboarding and permission explanation.
2. Sign-in.
3. Today dashboard.
4. Quick capture.
5. AI extraction review.
6. Event details and milestone timeline.
7. Registration status.
8. Reminder policy editor.
9. Calendar/upcoming deadlines.
10. Memory search and Q&A.
11. Memory detail with source.
12. Notification history.
13. Settings, privacy, integrations, and account deletion.

### Web
1. Sign-in.
2. Dashboard.
3. Events/opportunities.
4. Event details/timeline.
5. Tasks/reminders.
6. Memory library/search.
7. URL/text/file capture.
8. Notification history.
9. Settings/integrations.

### Browser extension
- “Capture this page” action.
- Preview page title and URL.
- User-triggered extraction.
- Review extracted fields and evidence.
- Save to account.
- Confirmation link to the saved event.

Show source evidence and uncertain fields. Make Complete, Snooze, and Reschedule easy. Distinguish registration, submission, and event dates. Never show “Reminder scheduled” until the database transaction and scheduling workflow succeed.

## 13. Acceptance tests

1. Share a supported hackathon page.
2. Extract title, source URL, registration URL, and available dates.
3. Keep missing dates unknown.
4. Review and confirm the event.
5. Persist event/milestones in PostgreSQL.
6. Create the expected reminder jobs.
7. Process a due job while the browser is closed.
8. Retry a transient notification failure without duplicate delivery.
9. Mark registration complete and stop only registration reminders.
10. Keep submission reminders active.
11. Search saved memory and open its source.
12. Prevent another account from reading the user's data.
13. Sync offline captures without duplicates.
14. Test account deletion.
15. Test Android/iOS capture on real devices and accurately document limitations.
16. Test scheduler restart, concurrent workers, duplicate API calls, timezone changes, provider outages, and simultaneous completion/due-job races.

Track extraction accuracy, correction rate for critical dates, duplicate reminder rate, due-job latency, delivery failure rate, capture-to-confirmation rate, registration completion rate, and user-reported false reminders. Do not claim impact before measuring it.

## 14. Implementation phases

### Phase 1: Foundation
FastAPI, PostgreSQL, SQLAlchemy/Alembic, authentication, authorization, Docker, configuration, migrations, tests, health checks.

### Phase 2: Capture + Gemini
URL/text/image capture, R2 signed uploads, Gemini structured extraction, schema validation, review screen, event/milestone persistence.

### Phase 3: Reminder engine
Policies, durable jobs, scheduler/worker, registration cadence, stop conditions, notifications, snooze/reschedule, retry/idempotency, delivery history.

### Phase 4: Memory + dashboard
Today's agenda, upcoming deadlines, saved source/summary, search, source-linked answers, event timeline.

### Phase 5: Mobile/browser capture
Android Share Sheet and shortcuts; iOS Share Extension and screenshot import; browser extension with user-triggered tab capture; device testing.

### Phase 6: Hardening and demo
Authorization tests, restart/retry tests, privacy/deletion, backups, monitoring, deployment, and end-to-end demo.

Out of MVP scope: silent access to every screen, automatic registration on third-party websites, unverified registration detection, autonomous form submission, Airflow, and unnecessary multi-provider AI complexity.

## 15. Suggested repository structure

```text
personal-memory-os/
├── apps/
│   ├── mobile/
│   ├── web/
│   └── browser-extension/
├── services/
│   ├── api/
│   ├── worker/
│   └── scheduler/
├── packages/
│   ├── shared-schemas/
│   └── client-sdk/
├── migrations/
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── scheduling/
│   └── security/
├── deploy/
├── docs/
├── .env.example
├── docker-compose.yml
└── README.md
```
Adapt this to the existing repository; inspect working code before restructuring.

## 16. Environment configuration

Example variable names only:
```dotenv
APP_ENV=development
APP_BASE_URL=http://localhost:8000
DATABASE_URL=postgresql+psycopg://user:password@localhost:5432/personal_memory_os

GEMINI_API_KEY=
GEMINI_MODEL=

CLOUDFLARE_R2_ACCOUNT_ID=
CLOUDFLARE_R2_ACCESS_KEY_ID=
CLOUDFLARE_R2_SECRET_ACCESS_KEY=
CLOUDFLARE_R2_BUCKET=
CLOUDFLARE_R2_ENDPOINT=

AUTH_PROVIDER=
AUTH_ISSUER_URL=
AUTH_AUDIENCE=
AUTH_CLIENT_ID=
AUTH_CLIENT_SECRET=

FCM_PROJECT_ID=
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_BUNDLE_ID=
APNS_PRIVATE_KEY=

EMAIL_PROVIDER=
EMAIL_API_KEY=
SENTRY_DSN=
```
These are placeholders, not credentials. Validate required settings at startup. Choose final auth and notification providers before implementing provider-specific code.

## 17. Deployment operations

Deploy API, worker, and scheduler as separately supervised processes/containers. They may share a host initially, but need separate process roles and health checks. Use HTTPS, restrict database access, keep staging separate from production, run migrations as a release step, configure graceful shutdown, monitor queues/jobs and provider errors, back up PostgreSQL, and test restores. CI should run linting, type checks, unit/integration tests, and migration checks.

## 18. Hackathon demo

1. Open a prepared hackathon page.
2. Click the browser extension or use the mobile Share Sheet.
3. Show extracted fields, deadline evidence, and registration URL.
4. Confirm the event.
5. Show the milestone timeline and reminder cadence.
6. Show registration status as Not started.
7. Simulate a due reminder using a test clock/fixture.
8. Mark registration complete and show registration reminders stop.
9. Show submission reminders remain active.
10. Search for the event and open its source.
11. Explain: Gemini interprets; PostgreSQL is the source of truth; the scheduler/worker executes policies; R2 stores media.
12. Be honest about device permissions and capture limitations.

## 19. Hackathon positioning

**Category:** Daily Life Enhancement  
**Lane:** Startups

**Problem:** Important opportunities and responsibilities are scattered across webpages, posters, documents, messages, and notes. People miss deadlines because they manually extract dates, create alarms, and track completion.

**Solution:** Personal Reminder & Memory OS captures user-selected content, extracts actions and dates with Gemini, stores source-linked memories, and executes status-aware reminders until an action is completed or expires.

**Differentiator:** It goes beyond summarization or a single alarm by connecting source-aware extraction, multiple milestones, repeated reminders, and explicit completion tracking.

**Trust principle:** AI proposes; the user confirms; the backend validates and schedules; the user can inspect and correct the result.

Report measured demo metrics only: extraction accuracy, time from capture to confirmed reminder, duplicate/false reminder rate, and successful job processing.

## 20. Decisions to settle before implementation

1. Confirm whether the current mobile app is Flutter.
2. Reuse the existing web framework.
3. Select the identity provider.
4. Select hosting for API, worker, and scheduler.
5. Choose FCM/APNs and whether email is required.
6. Configure the supported Gemini model.
7. Decide which browsers the extension will support.
8. Start with explicit share/capture actions; add Android-only accessibility/overlay capabilities only after policy and permission review.
9. Make reminder cadence configurable with explicit stop conditions.
10. Audit the existing repository and preserve working code before making structural changes.

## Final engineering rule

Use PostgreSQL as the source of truth, Gemini as an interpretation service, Cloudflare R2 for private media, and a durable scheduler/worker for reminders. Keep platform capture adapters separate from the core backend so Android, iOS, web, and browser extension clients can evolve independently. No Airflow dependency is needed.
