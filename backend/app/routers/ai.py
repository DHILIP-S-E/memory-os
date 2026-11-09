"""
AI router: natural-language reminder parsing and event extraction with Gemini.
Every model call is server-side (FastAPI -> llm_service -> gemini); the apps never call the model.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator

from app.auth import get_current_user_id
from app.services.ai_consent import require_ai
import logging

from app.services.gemini import AIUnavailable
from app.services.llm_service import parse_reminder, extract_event
from app.validation import clean_text, optional_http_url

router = APIRouter()
logger = logging.getLogger(__name__)


class ParseReminderRequest(BaseModel):
    text: str
    timezone: str = "UTC"


MAX_EXTRACT_TEXT = 20_000


class ExtractEventRequest(BaseModel):
    text: str
    source_url: Optional[str] = None  # the page the text came from, if any

    @field_validator("text")
    @classmethod
    def _text(cls, v):
        return clean_text(v, "Text", max_len=MAX_EXTRACT_TEXT)

    @field_validator("source_url")
    @classmethod
    def _source(cls, v):
        return optional_http_url(v, "Source link")


@router.post("/parse-reminder")
async def parse_reminder_endpoint(
    body: ParseReminderRequest,
    user_id: str = Depends(require_ai),
):
    """
    Parse natural language into a structured reminder.

    Example input: "Remind me every Monday at 9am to check new hackathons"
    Example output:
    {
      "title": "Check new hackathons",
      "type": "recurring",
      "scheduled_at": "2026-10-05T09:00:00+05:30",
      "priority": "low",
      "offsets": []
    }
    """
    try:
        result = parse_reminder(body.text, body.timezone)
        return result
    except AIUnavailable as e:
        # Safe to show: "not configured", "could not reach", or an HTTP status. Never model output.
        raise HTTPException(status_code=503, detail=str(e))
    except ValueError:
        raise HTTPException(status_code=422, detail="The AI could not read a reminder from that text. Try rewording it.")
    except Exception:
        logger.exception("AI read a reminder failed")
        raise HTTPException(status_code=503, detail="The AI service had a problem. Please try again.")


@router.post("/extract-event")
async def extract_event_endpoint(
    body: ExtractEventRequest,
    user_id: str = Depends(require_ai),
):
    """
    Extract structured event info from pasted text or a URL description.

    Example input: "Spring Hackathon Oct 4-5, register by Oct 1, Bangalore"
    Example output:
    {
      "title": "Spring Hackathon",
      "event_type": "hackathon",
      "start_at": "2026-10-04T09:00:00",
      "end_at": "2026-10-05T18:00:00",
      "location": "Bangalore",
      "registration_deadline": "2026-10-01T23:59:00",
      "is_virtual": false
    }
    """
    try:
        result = extract_event(body.text, body.source_url)
        return result
    except AIUnavailable as e:
        # Safe to show: "not configured", "could not reach", or an HTTP status. Never model output.
        raise HTTPException(status_code=503, detail=str(e))
    except ValueError:
        raise HTTPException(status_code=422, detail="The AI could not find an event from that text. Try rewording it.")
    except Exception:
        logger.exception("AI find an event failed")
        raise HTTPException(status_code=503, detail="The AI service had a problem. Please try again.")
