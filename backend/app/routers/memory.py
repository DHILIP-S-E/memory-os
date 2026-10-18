"""
Memory router — list, search, and AI Q&A for personal memory documents.
"""

import json
from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, field_validator
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.validation import clean_text
from app.auth import get_current_user_id
from app.database import get_db
from app.models.memory import MemoryDocument
from app.services.llm_service import answer_memory_question

router = APIRouter()


class AskRequest(BaseModel):
    question: str

    @field_validator("question")
    @classmethod
    def _question(cls, v):
        return clean_text(v, "Question", max_len=2000)


@router.get("")
async def list_memory(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Return all memory documents for the user, newest first."""
    result = await db.execute(
        select(MemoryDocument)
        .where(MemoryDocument.user_id == user_id)
        .order_by(MemoryDocument.event_date.desc())
    )
    return [d.to_dict() for d in result.scalars().all()]


@router.get("/search")
async def search_memory(
    q: str = Query(..., min_length=1, description="Search query"),
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """
    Keyword search across memory documents.
    Searches: event_title, overview, search_vector (concatenated topics + content).
    """
    terms = q.strip().split()[:5]  # cap at 5 terms
    conditions = []
    for term in terms:
        like = f"%{term}%"
        conditions.append(MemoryDocument.search_vector.ilike(like))
        conditions.append(MemoryDocument.event_title.ilike(like))
        conditions.append(MemoryDocument.overview.ilike(like))

    result = await db.execute(
        select(MemoryDocument)
        .where(
            MemoryDocument.user_id == user_id,
            or_(*conditions),
        )
        .order_by(MemoryDocument.event_date.desc())
        .limit(20)
    )
    return [d.to_dict() for d in result.scalars().all()]


@router.post("/ask")
async def ask_memory(
    body: AskRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """
    Memory Q&A grounded in the user's own documents, answered by the strong Gemini model.

    Flow:
    1. Keyword search memory_documents for relevant context
    2. Fall back to most recent 5 documents if no keyword match
    3. Build context string from matched documents
    4. Call the strong Gemini model with context + question
    5. Return grounded answer with source citations

    Every answer is traceable to stored memory — no hallucination from training data.
    """
    # Step 1: keyword search for relevant documents
    words = body.question.lower().split()[:6]
    conditions = []
    for word in words:
        if len(word) > 3:  # skip short words (a, the, is, etc.)
            like = f"%{word}%"
            conditions.append(MemoryDocument.search_vector.ilike(like))
            conditions.append(MemoryDocument.event_title.ilike(like))

    docs = []
    if conditions:
        result = await db.execute(
            select(MemoryDocument)
            .where(
                MemoryDocument.user_id == user_id,
                or_(*conditions),
            )
            .order_by(MemoryDocument.event_date.desc())
            .limit(5)
        )
        docs = result.scalars().all()

    # Step 2: fall back to most recent if no keyword match
    if not docs:
        result = await db.execute(
            select(MemoryDocument)
            .where(MemoryDocument.user_id == user_id)
            .order_by(MemoryDocument.event_date.desc())
            .limit(5)
        )
        docs = result.scalars().all()

    # Step 3+4+5: call Gemini with context
    return answer_memory_question(body.question, docs)


@router.get("/{document_id}")
async def get_memory_document(
    document_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MemoryDocument).where(
            MemoryDocument.id == document_id,
            MemoryDocument.user_id == user_id,
        )
    )
    doc = result.scalar_one_or_none()
    if not doc:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Memory document not found")
    return doc.to_dict()
