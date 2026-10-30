import assert from 'node:assert/strict';
import { test } from 'node:test';
import { errorMessage } from '../src/errors.js';
import {
  buildEventBody, fieldNotes, fromLocalInput, isHttpUrl, toLocalInput, trimPageText, MAX_PAGE_TEXT,
} from '../src/proposal.js';

test('page text is collapsed and capped, never unbounded', () => {
  assert.equal(trimPageText('  Hello \n\n  world\t!  '), 'Hello world !');
  assert.equal(trimPageText('x'.repeat(50000)).length, MAX_PAGE_TEXT);
  assert.equal(trimPageText(null), '');
});

test('only http and https links are accepted', () => {
  assert.equal(isHttpUrl('https://example.org/a'), true);
  for (const bad of ['javascript:alert(1)', 'data:text/html,x', 'ftp://x.co', 'example.org', '', null]) {
    assert.equal(isHttpUrl(bad), false, String(bad));
  }
});

test('a zone-less AI date-time is kept as the wall-clock time the page meant', () => {
  assert.equal(toLocalInput('2026-11-05T23:59:00'), '2026-11-05T23:59');
  assert.equal(toLocalInput('2026-11-05'), '2026-11-05T09:00');
  for (const bad of [null, '', 'next friday', '32/13/2026']) assert.equal(toLocalInput(bad), '', String(bad));
});

test('a date-time with a zone is shown in the users own clock and round-trips', () => {
  const iso = '2026-11-05T18:30:00Z';
  const local = toLocalInput(iso);
  assert.match(local, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
  assert.equal(new Date(fromLocalInput(local)).getTime(), new Date(iso).getTime());
});

test('an empty or invalid input is null, never an invented date', () => {
  for (const bad of ['', '   ', null, undefined, 'soon']) assert.equal(fromLocalInput(bad), null);
});

test('notes show the evidence, the assumed time and what is missing', () => {
  const proposal = {
    registration_deadline: '2026-11-05T23:59:00',
    submission_deadline: null,
    assumed_times: ['registration_deadline'],
    evidence: { registration_deadline: 'Register by 5 November' },
    missing_fields: ['submission_deadline'],
  };
  assert.deepEqual(fieldNotes(proposal, 'registration_deadline'),
    { evidence: 'Register by 5 November', assumedTime: true, missing: false });
  assert.deepEqual(fieldNotes(proposal, 'submission_deadline'), { evidence: null, assumedTime: false, missing: true });
  assert.equal(fieldNotes(undefined, 'start_at').missing, true);
});

const base = { title: ' Hack ', event_type: 'hackathon', start_at: '2026-11-20T09:00', end_at: '', registration_deadline: '', submission_deadline: '' };

test('a confirmed draft becomes a request body with its milestones as deadlines', () => {
  const { body, error } = buildEventBody(
    { ...base, registration_deadline: '2026-11-05T23:59', submission_deadline: '2026-11-22T23:59', registration_url: 'https://example.org/r' },
    'Asia/Kolkata');
  assert.equal(error, undefined);
  assert.equal(body.title, 'Hack');
  assert.equal(body.timezone, 'Asia/Kolkata');
  assert.deepEqual(body.deadlines.map((d) => d.deadline_type), ['registration', 'submission']);
  assert.equal(body.registration_url, 'https://example.org/r');
  assert.equal('end_at' in body, false);
});

test('a missing start is asked for, not guessed', () => {
  assert.match(buildEventBody({ ...base, start_at: '' }, 'UTC').error, /starts/);
});

test('bad drafts say what to fix', () => {
  assert.match(buildEventBody({ ...base, title: '  ' }, 'UTC').error, /title/i);
  assert.match(buildEventBody({ ...base, title: 'x'.repeat(501) }, 'UTC').error, /too long/);
  assert.match(buildEventBody({ ...base, end_at: '2026-11-19T09:00' }, 'UTC').error, /end before/);
  assert.match(buildEventBody({ ...base, end_at: 'nope' }, 'UTC').error, /end time/);
  assert.match(buildEventBody({ ...base, registration_deadline: 'nope' }, 'UTC').error, /Registration deadline/);
  assert.match(buildEventBody({ ...base, event_url: 'javascript:alert(1)' }, 'UTC').error, /http/);
});

test('an unknown event type falls back to custom', () => {
  assert.equal(buildEventBody({ ...base, event_type: 'party' }, 'UTC').body.event_type, 'custom');
});

test('errors are plain sentences, using the backends own reason when it gave one', () => {
  assert.match(errorMessage(0), /Can't reach the server/);
  assert.equal(errorMessage(400, { detail: 'Invalid email or password' }), 'Invalid email or password');
  assert.equal(errorMessage(422, { detail: [{ msg: 'Value error, Title cannot be empty' }] }), 'Title cannot be empty');
  assert.match(errorMessage(401, {}), /sign in again/);
  assert.match(errorMessage(503, {}), /server had a problem/);
  assert.match(errorMessage(404, {}), /Something went wrong/);
});
