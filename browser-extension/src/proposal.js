// Pure helpers for the review screen: no DOM, no network, so they can be tested on their own.

export const MAX_PAGE_TEXT = 12000;
export const EVENT_TYPES = [
  'hackathon', 'conference', 'workshop', 'webinar', 'meetup',
  'meeting', 'appointment', 'deadline', 'custom',
];

/** Collapse whitespace and cap the length, so only a bounded amount of the page is ever sent. */
export function trimPageText(text, max = MAX_PAGE_TEXT) {
  return String(text ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
}

export function isHttpUrl(value) {
  try {
    const url = new URL(String(value));
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch {
    return false;
  }
}

const pad = (n) => String(n).padStart(2, '0');
const HAS_ZONE = /(Z|[+-]\d{2}:?\d{2})$/i;

/** An ISO date-time from the AI, as the "YYYY-MM-DDTHH:mm" a datetime-local input needs ('' if unusable). */
export function toLocalInput(iso) {
  if (typeof iso !== 'string' || !iso.trim()) return '';
  const text = iso.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return `${text}T09:00`;
  if (!HAS_ZONE.test(text)) {
    // Written without a zone: it is already the wall-clock time the page meant.
    const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/.exec(text);
    return m ? `${m[1]}T${m[2]}` : '';
  }
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) return '';
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** A datetime-local value (the user's own clock) as the UTC instant the API stores, or null. */
export function fromLocalInput(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/** What to show next to a field: the quote it came from, whether its time was assumed, whether it was missing. */
export function fieldNotes(proposal, field) {
  const value = proposal?.[field];
  return {
    evidence: (proposal?.evidence && proposal.evidence[field]) || null,
    assumedTime: Array.isArray(proposal?.assumed_times) && proposal.assumed_times.includes(field),
    missing: !value || (Array.isArray(proposal?.missing_fields) && proposal.missing_fields.includes(field)),
  };
}

/**
 * The reviewed form as an API request body, or { error } saying what to fix.
 * Nothing is saved without the user pressing Save; this only checks what they confirmed.
 */
export function buildEventBody(draft, timezone) {
  const title = String(draft.title ?? '').trim();
  if (!title) return { error: 'Enter a title.' };
  if (title.length > 500) return { error: 'The title is too long (500 characters at most).' };
  const start = fromLocalInput(draft.start_at);
  if (!start) return { error: 'Enter when the event starts. The page did not say, so it cannot be guessed.' };
  const end = fromLocalInput(draft.end_at);
  if (draft.end_at && !end) return { error: 'The end time is not a valid date.' };
  if (end && end < start) return { error: 'The event cannot end before it starts.' };
  for (const field of ['event_url', 'registration_url']) {
    if (draft[field] && !isHttpUrl(draft[field])) return { error: 'Links must start with http:// or https://.' };
  }

  const deadlines = [];
  for (const [field, type, label] of [
    ['registration_deadline', 'registration', 'Registration deadline'],
    ['submission_deadline', 'submission', 'Submission deadline'],
  ]) {
    if (!draft[field]) continue;
    const at = fromLocalInput(draft[field]);
    if (!at) return { error: `${label} is not a valid date.` };
    deadlines.push({ title: label, deadline_type: type, deadline_at: at });
  }

  const body = {
    title,
    event_type: EVENT_TYPES.includes(draft.event_type) ? draft.event_type : 'custom',
    start_at: start,
    timezone,
    is_virtual: Boolean(draft.is_virtual),
    deadlines,
  };
  if (end) body.end_at = end;
  for (const field of ['description', 'location', 'organizer', 'event_url', 'registration_url']) {
    const value = String(draft[field] ?? '').trim();
    if (value) body[field] = value;
  }
  return { body };
}
