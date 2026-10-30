import { WEB_URL } from './config.js';
import { api, hasSession, signIn, signOut } from './src/api.js';
import { buildEventBody, EVENT_TYPES, fieldNotes, toLocalInput, trimPageText } from './src/proposal.js';

const $ = (id) => document.getElementById(id);
const DATE_FIELDS = ['start_at', 'end_at', 'registration_deadline', 'submission_deadline'];
const TEXT_FIELDS = ['title', 'registration_url', 'event_url', 'location'];

let page = null; // { title, url, selection, text }

function show(name) {
  for (const section of document.querySelectorAll('main > section')) section.hidden = section.id !== name;
  $('signout-btn').hidden = name === 'signin';
}

function say(id, text, ok = false) {
  const el = $(id);
  el.textContent = text || '';
  el.classList.toggle('ok', ok);
}

/** Run an action with its button disabled, and show any failure as a plain message. */
async function guarded(button, messageId, action) {
  button.disabled = true;
  say(messageId, '');
  try {
    await action();
  } catch (error) {
    say(messageId, error.message || 'Something went wrong. Please try again.');
  } finally {
    button.disabled = false;
  }
}

// ── Reading the page: only after the user opened the popup (activeTab) ─────────────────────────────
async function readActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id || !/^https?:/i.test(tab.url || '')) {
    throw new Error('Open a web page first. Browser pages cannot be captured.');
  }
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => ({
      title: document.title,
      url: location.href,
      selection: String(window.getSelection() || ''),
      text: document.body ? document.body.innerText : '',
    }),
  });
  return result;
}

function textToSend() {
  const selected = trimPageText(page.selection);
  return $('use-selection').checked && selected ? selected : trimPageText(page.text);
}

function refreshCharCount() {
  $('chars').textContent = String(textToSend().length);
}

async function openCapture() {
  show('capture');
  say('capture-msg', '');
  try {
    page = await readActiveTab();
  } catch (error) {
    page = null;
    $('page-title').textContent = '';
    $('page-url').textContent = '';
    $('extract-btn').disabled = true;
    $('memory-btn').disabled = true;
    say('capture-msg', error.message);
    return;
  }
  $('extract-btn').disabled = false;
  $('memory-btn').disabled = false;
  $('page-title').textContent = page.title || '(untitled page)';
  $('page-url').textContent = page.url;
  const hasSelection = Boolean(trimPageText(page.selection));
  $('selection-row').hidden = !hasSelection;
  $('use-selection').checked = hasSelection;
  refreshCharCount();
}

// ── Review ─────────────────────────────────────────────────────────────────────────────────────────
function fillReview(proposal) {
  $('f-type').replaceChildren(...EVENT_TYPES.map((type) => new Option(type, type)));
  $('f-type').value = EVENT_TYPES.includes(proposal.event_type) ? proposal.event_type : 'custom';
  for (const field of TEXT_FIELDS) $(`f-${field}`).value = proposal[field] || '';
  for (const field of DATE_FIELDS) $(`f-${field}`).value = toLocalInput(proposal[field]);
  for (const field of [...DATE_FIELDS, 'registration_url']) {
    const notes = fieldNotes(proposal, field);
    const parts = [];
    if (notes.missing) parts.push('Not found on the page.');
    if (notes.assumedTime && !notes.missing) parts.push('The time was not stated, please check it.');
    if (notes.evidence) parts.push(`From the page: "${notes.evidence}"`);
    const el = $(`n-${field}`);
    if (el) el.textContent = parts.join(' ');
  }
  if (proposal.ambiguous_dates?.length) {
    say('review-msg', `These dates could be read two ways, please check them: ${proposal.ambiguous_dates.join(', ')}`);
  } else {
    say('review-msg', '');
  }
  show('review');
}

function readDraft() {
  const draft = { event_type: $('f-type').value, description: '', organizer: '', is_virtual: false };
  for (const field of [...TEXT_FIELDS, ...DATE_FIELDS]) draft[field] = $(`f-${field}`).value;
  draft.registration_deadline = $('f-registration_deadline').value;
  draft.submission_deadline = $('f-submission_deadline').value;
  return draft;
}

let lastProposal = null;

async function extract() {
  const text = textToSend();
  if (!text) throw new Error('There is no readable text on this page.');
  const proposal = await api('/ai/extract-event', { method: 'POST', body: { text, source_url: page.url } });
  lastProposal = proposal;
  fillReview({ ...proposal, event_url: proposal.event_url || page.url });
}

async function saveEvent() {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const { body, error } = buildEventBody({ ...readDraft(), description: lastProposal?.description || '' }, timezone);
  if (error) throw new Error(error);

  const event = await api('/events', { method: 'POST', body });
  let text = 'Your event is saved.';
  if ($('f-reminders').checked) {
    try {
      const reminders = await api(`/events/${event.id}/reminder-policy`, { method: 'POST' });
      text = reminders.length
        ? `Your event is saved and ${reminders.length} reminder${reminders.length === 1 ? ' is' : 's are'} scheduled.`
        : 'Your event is saved. No reminders were created because every date is already in the past.';
    } catch (reminderError) {
      text = `Your event is saved, but the reminders could not be created: ${reminderError.message}`;
    }
  }
  $('done-text').textContent = text;
  $('done-link').href = `${WEB_URL}/events/${event.id}`;
  show('done');
}

async function saveLink() {
  await api('/captures/link', { method: 'POST', body: { url: page.url } });
  say('capture-msg', 'Saved to your memory.', true);
}

// ── Wiring ─────────────────────────────────────────────────────────────────────────────────────────
$('signin-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('signin-btn'), 'signin-msg', async () => {
    await signIn($('email').value.trim(), $('password').value);
    $('password').value = '';
    await openCapture();
  });
});
$('signout-btn').addEventListener('click', async () => {
  await signOut();
  show('signin');
});
$('use-selection').addEventListener('change', refreshCharCount);
$('extract-btn').addEventListener('click', () => guarded($('extract-btn'), 'capture-msg', extract));
$('memory-btn').addEventListener('click', () => guarded($('memory-btn'), 'capture-msg', saveLink));
$('review-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('save-btn'), 'review-msg', saveEvent);
});
$('back-btn').addEventListener('click', () => show('capture'));
$('again-btn').addEventListener('click', openCapture);

(async () => {
  if (await hasSession()) await openCapture();
  else show('signin');
})();
