"""
DEVELOPMENT ONLY. Never imported by the app or the worker; run by hand against a dev server.

Create (or reset) a DEMO account with sample data, through the public API.

    python scripts/seed_demo.py                      # against http://localhost:8000
    python scripts/seed_demo.py --base-url http://localhost:8000

The account is throwaway and its credentials are in this file, so it only ever
holds made-up data. Safe to re-run: it deletes the demo account first, then rebuilds it.
Dates are relative to "now", so the demo always has something overdue, due today and coming up.
"""

import argparse
import sys
import time
from datetime import datetime, timedelta, timezone

import httpx

DEFAULT_URL = "http://localhost:8000"  # a dev server; pass --base-url for any other
EMAIL = "judge-demo@example.com"
PASSWORD = "ZeroToShipped2026!"

NOTES = [
    "Vector search lets an assistant retrieve notes by meaning to answer from private data. "
    "The speaker stressed that the model only interprets: deterministic code should do the scheduling.",
    "RAG reduces hallucination because answers are grounded in retrieved documents. "
    "Chunk size matters: 300 tokens with 20 percent overlap worked well in the demo.",
    "I need to submit the hackathon prototype by the 20th and follow up with Priya about her feedback next week.",
]


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=DEFAULT_URL)
    base = parser.parse_args().base_url.rstrip("/")
    http = httpx.Client(base_url=base, timeout=60)

    def step(msg: str) -> None:
        print(f"- {msg}", flush=True)

    # Start clean: remove an existing demo account (and everything in it).
    r = http.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    if r.status_code == 200:
        http.delete("/account", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
        step("removed the previous demo account")
    r = http.post("/auth/register", json={"email": EMAIL, "password": PASSWORD, "display_name": "Judge Demo"})
    r.raise_for_status()
    auth = {"Authorization": f"Bearer {r.json()['access_token']}"}
    step(f"created {EMAIL}")

    def post(path: str, body: dict) -> dict:
        resp = http.post(path, json=body, headers=auth)
        resp.raise_for_status()
        return resp.json()

    now = datetime.now(timezone.utc)
    next_monday = (now + timedelta(days=(7 - now.weekday()) % 7 or 7)).replace(hour=3, minute=30, second=0, microsecond=0)

    # --- reminders: one overdue, one soon, a deadline, a recurring one, a conditional one
    post("/reminders", {"title": "Pay cloud bill", "reminder_type": "deadline", "priority": "high",
                        "scheduled_at": iso(now - timedelta(days=1))})
    post("/reminders", {"title": "Team standup", "reminder_type": "time", "priority": "medium",
                        "scheduled_at": iso(now + timedelta(hours=2))})
    deadline = post("/reminders", {"title": "Submit hackathon prototype", "reminder_type": "deadline", "priority": "high",
                                   "scheduled_at": iso(now + timedelta(days=18)), "offsets": ["-1d", "-3h"]})
    post("/reminders", {"title": "Weekly review", "reminder_type": "recurring", "priority": "low",
                        "recurrence_rule": "FREQ=WEEKLY;BYDAY=MO", "scheduled_at": iso(next_monday)})
    post("/reminders", {"title": "Check the prototype was actually submitted", "reminder_type": "conditional",
                        "priority": "medium", "depends_on_id": deadline["id"],
                        "scheduled_at": iso(now + timedelta(days=17))})
    step("created 5 reminders (overdue, today, deadline, recurring, conditional)")

    # --- an upcoming event with deadlines, and a past workshop with notes
    post("/events", {
        "title": "Zero to Shipped Demo Day", "event_type": "hackathon", "start_at": iso(now + timedelta(days=9)),
        "location": "Online", "is_virtual": True,
        "deadlines": [
            {"title": "Registration closes", "deadline_type": "registration", "deadline_at": iso(now + timedelta(days=4))},
            {"title": "Prototype submission", "deadline_type": "submission", "deadline_at": iso(now + timedelta(days=8))},
        ],
    })
    workshop = post("/events", {"title": "Vector Search Workshop", "event_type": "workshop",
                                "start_at": iso(now - timedelta(days=3)), "location": "Bangalore"})
    http.patch(f"/events/{workshop['id']}", json={"status": "completed"}, headers=auth).raise_for_status()
    step("created 2 events (the workshop is marked completed)")

    note_ids = [post("/captures/note", {"content": text, "event_id": workshop["id"]})["id"] for text in NOTES]
    step(f"added {len(note_ids)} notes to the workshop; waiting for the AI to process them")

    pending = set(note_ids)
    for _ in range(40):
        for cid in list(pending):
            status = http.get(f"/captures/{cid}", headers=auth).json()["processing_status"]
            if status in ("processed", "failed"):
                pending.discard(cid)
        if not pending:
            break
        time.sleep(3)
    if pending:
        print("WARNING: some notes were not processed in time:", pending)

    summary = http.post(f"/events/{workshop['id']}/generate-summary", headers=auth, timeout=120)
    summary.raise_for_status()
    step(f"generated the workshop's memory summary ({len(summary.json().get('key_topics', []))} topics)")

    answer = http.post("/memory/ask", json={"question": "What did I learn about vector search?"}, headers=auth, timeout=120)
    answer.raise_for_status()
    print(f"\nTry asking: 'What did I learn about vector search?'\n  -> {answer.json()['answer'][:160]}")
    print(f"\nDemo login: {EMAIL} / {PASSWORD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
