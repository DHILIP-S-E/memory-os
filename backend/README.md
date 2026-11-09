# Personal Memory OS — Backend

FastAPI + PostgreSQL + Google Gemini + Cloudflare R2 backend for the Personal Memory OS Flutter app.
There is no AWS dependency.

```
Flutter App  →  FastAPI (this)  →  PostgreSQL (data and the job queue)
                               →  Cloudflare R2 (private files, S3-compatible API)
                               →  Google Gemini (all AI calls, server side only)
                               →  Firebase Cloud Messaging (push)
Worker (python -m app.worker)  →  delivers reminders, reads captured files
```

---

## Prerequisites

- Python 3.11+
- PostgreSQL (Neon, Supabase, or any server)
- Optional, each enables one feature: a Gemini API key, a Cloudflare R2 bucket and API token,
  a Firebase service-account key (push), Google OAuth client IDs (Google sign-in)

---

## Setup

```bash
# 1. Enter the backend directory
cd backend

# 2. Create and activate virtual environment
python -m venv venv
# Windows:
venv\Scripts\activate
# Mac/Linux:
source venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Copy and fill in environment variables
cp .env.example .env
# Edit .env with your real values (see .env.example for all keys)
```

---

## Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (required; the server refuses to start without it) |
| `JWT_SECRET` | 32+ random characters; signs access tokens. Without it every request is refused |
| `GOOGLE_CLIENT_IDS` | Google OAuth client IDs, comma-separated |
| `CORS_ORIGINS` | Allowed browser origins, comma-separated |
| `GEMINI_API_KEY` | Google Gemini key; without it AI routes answer 503 |
| `GEMINI_MODEL_FAST` / `GEMINI_MODEL_STRONG` / `GEMINI_EMBEDDING_MODEL` | Model names (settings, not code) |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | Cloudflare R2 for private files |
| `FCM_PROJECT_ID`, `FCM_CREDENTIALS_FILE` | Firebase Cloud Messaging push |

On startup the server logs a warning for each optional setting that is missing.

> **Never commit a real `.env` file.** It is in `.gitignore`.

---

## Database Migration

```bash
# Run from backend/ directory with venv active
alembic upgrade head
```

This creates all tables:
- `reminders`, `events`, `event_deadlines`
- `captures`, `memory_documents`
- `notification_deliveries`

---

## Run the Development Server

```bash
uvicorn app.main:app --reload --port 8000
```

API is available at:
- **Swagger UI:** http://localhost:8000/docs
- **Health check:** http://localhost:8000/health

---

## API Endpoints

### Reminders
| Method | Path | Description |
|---|---|---|
| `POST` | `/reminders` | Create reminder |
| `GET` | `/reminders` | List reminders (filter by status, type) |
| `GET` | `/reminders/{id}` | Get single reminder |
| `PATCH` | `/reminders/{id}` | Update reminder |
| `DELETE` | `/reminders/{id}` | Delete reminder |

### Events
| Method | Path | Description |
|---|---|---|
| `POST` | `/events` | Create event + deadlines |
| `GET` | `/events` | List events |
| `GET` | `/events/{id}` | Event detail with deadlines + capture counts |
| `PATCH` | `/events/{id}` | Update event |
| `DELETE` | `/events/{id}` | Delete event (cascades deadlines) |
| `POST` | `/events/{id}/deadlines` | Add deadline |
| `POST` | `/events/{id}/generate-summary` | Generate AI summary (strong model) |
| `GET` | `/events/{id}/summary` | Get existing summary |

### Captures
| Method | Path | Description |
|---|---|---|
| `POST` | `/captures/upload-url` | Get R2 signed PUT URL |
| `POST` | `/captures` | Register capture after upload |
| `POST` | `/captures/note` | Save text note (no file) |
| `POST` | `/captures/link` | Save URL link |
| `GET` | `/captures` | List captures |
| `GET` | `/captures/{id}/download-url` | Get R2 signed GET URL |
| `PATCH` | `/captures/{id}` | Update AI results |
| `DELETE` | `/captures/{id}` | Delete (removes the R2 object) |

### Memory
| Method | Path | Description |
|---|---|---|
| `GET` | `/memory` | List memory documents |
| `GET` | `/memory/search?q=` | Keyword search |
| `POST` | `/memory/ask` | RAG Q&A (strong model + grounded citations) |
| `GET` | `/memory/{id}` | Single memory document |

### AI
| Method | Path | Description |
|---|---|---|
| `POST` | `/ai/parse-reminder` | NLP → structured reminder (fast model) |
| `POST` | `/ai/extract-event` | Text → structured event (fast model) |

### Account, devices and event policy
| Method | Path | Description |
|---|---|---|
| `GET` | `/account/export` | All of the user's data as JSON |
| `DELETE` | `/account` | Delete everything: DB rows, R2 files, pending jobs |
| `POST` | `/devices` | Register an FCM token for push |
| `GET` | `/events/{id}/reminder-policy` | Preview the smart reminder plan for an event |
| `POST` | `/events/{id}/reminder-policy` | Create the confirmed reminders |

---

## Tests

```bash
pip install -r requirements-dev.txt
python -m pytest
```

Property-based tests (hypothesis) cover reminder parsing, fire-time scheduling,
quiet hours, event policy and conditional reminders.

---

## Connect Flutter to Backend

In the Flutter app, enable real backend mode:

```bash
flutter run --dart-define=USE_REAL_BACKEND=true --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

| Device | `BACKEND_URL` |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |
| Physical device (same Wi-Fi) | `http://192.168.x.x:8000` |
| Production | `https://api.your-domain.com` |

---

## Architecture Notes

- **Flutter → FastAPI:** all API calls use `ApiClient` with the app's own access token
- **FastAPI → Gemini:** `services/gemini.py` handles every model call (timeouts, retries on
  temporary errors); Flutter never calls the model directly
- **FastAPI → R2:** signed URLs generated server-side; Flutter uploads directly to R2
- **Auth:** access tokens signed with `JWT_SECRET`, checked in `auth.py` on every protected route
- **Background work:** jobs live in Postgres; `python -m app.worker` runs them with retry and
  backoff, and marks a job `failed` (with its error) after its last attempt
- **AI principles enforced:**
  - AI suggests, user confirms; no silent reminder/event creation from AI output
  - Every memory answer is grounded in stored captures
  - The model never schedules anything; server code does
  - AI failures return a real HTTP error (503 or 502); the server never invents a substitute answer
- **Auth fails closed:** without `JWT_SECRET` every request is refused (503). For local
  development only, set `ALLOW_INSECURE_DEV_AUTH=true` to accept unverified tokens.
- `scripts/seed_demo.py` is a dev-only helper for filling a dev server with sample data; the app never imports it.
