import { useState, useRef } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import EmptyState from '../../components/ui/EmptyState';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import {
  getUploadUrl,
  registerCapture,
  createTextNote,
  saveLink,
  listCaptures,
  uploadFileToS3,
} from './capturesApi';
import { listEvents } from '../events/eventsApi';
import type { Capture, AIResult } from '../../types/index';
import { apiErrorMessage } from '../../lib/apiError';
import { itemText } from '../../lib/itemText';
import { reminderFromAction, type ActionItem } from '../../lib/actionReminder';
import { createReminder } from '../reminders/remindersApi';

type CaptureTab = 'note' | 'link' | 'photo' | 'document';

const CAPTURE_ICONS: Record<string, string> = {
  note: '📝',
  link: '🔗',
  photo: '📸',
  voice: '🎙️',
  document: '📄',
};

// ──────────────────────────────────────────────────────────────────────────────
// AI Result expand panel
// ──────────────────────────────────────────────────────────────────────────────
function ActionRow({ action }: { action: ActionItem }) {
  const queryClient = useQueryClient();
  const draft = reminderFromAction(action);
  const [state, setState] = useState<'idle' | 'saving' | 'done'>('idle');
  const [error, setError] = useState<string | null>(null);

  async function addReminder() {
    if (!draft) return;
    setState('saving');
    setError(null);
    try {
      await createReminder(draft);
      await queryClient.invalidateQueries({ queryKey: ['reminders'] });
      setState('done');
    } catch (err: unknown) {
      setError(apiErrorMessage(err, 'Could not create the reminder'));
      setState('idle');
    }
  }

  return (
    <li className="flex items-start justify-between gap-3 list-none">
      <span>{itemText(action)}</span>
      {draft && (
        <Button size="sm" variant="secondary" disabled={state !== 'idle'} onClick={addReminder}>
          {state === 'done' ? 'Reminder added' : state === 'saving' ? 'Adding…' : 'Make reminder'}
        </Button>
      )}
      {error && <span className="text-error text-xs w-full">{error}</span>}
    </li>
  );
}

function AiResultPanel({ result }: { result: AIResult }) {
  return (
    <div className="mt-3 bg-background rounded-lg p-3 space-y-2 border border-border text-sm">
      <p className="text-textSecondary text-xs font-medium uppercase tracking-wide">AI Summary</p>
      {result.summary && <p className="text-textPrimary">{result.summary}</p>}
      {result.topics.length > 0 && (
        <div>
          <p className="text-textMuted text-xs mb-1">Topics</p>
          <div className="flex flex-wrap gap-1">
            {result.topics.map((t, i) => (
              <span key={i} className="px-2 py-0.5 rounded-full text-xs bg-indigo-900 text-indigo-200">
                {t}
              </span>
            ))}
          </div>
        </div>
      )}
      {result.key_points.length > 0 && (
        <div>
          <p className="text-textMuted text-xs mb-1">Key Points</p>
          <ul className="list-disc list-inside text-textSecondary space-y-0.5">
            {result.key_points.map((k, i) => <li key={i}>{k}</li>)}
          </ul>
        </div>
      )}
      {result.actions.length > 0 && (
        <div>
          <p className="text-textMuted text-xs mb-1">Actions</p>
          <ul className="text-textSecondary space-y-2">
            {result.actions.map((a, i) => <ActionRow key={i} action={a} />)}
          </ul>
        </div>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Single capture card in the "Recent Captures" list
// ──────────────────────────────────────────────────────────────────────────────
function CaptureCard({ capture }: { capture: Capture }) {
  const [expanded, setExpanded] = useState(false);
  const icon = CAPTURE_ICONS[capture.capture_type] ?? '📎';

  return (
    <Card variant="card" className="space-y-1">
      <div className="flex items-center gap-3">
        <span className="text-xl">{icon}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-textPrimary text-sm font-medium capitalize">
              {capture.capture_type}
            </span>
            <Badge label={capture.processing_status} />
          </div>
          {capture.content && (
            <p className="text-textMuted text-xs mt-0.5 truncate">{capture.content}</p>
          )}
          <p className="text-textMuted text-xs mt-0.5">
            {format(new Date(capture.created_at), 'PPp')}
          </p>
        </div>
        {capture.ai_result && (
          <Button variant="ghost" size="sm" onClick={() => setExpanded(v => !v)}>
            {expanded ? '▲' : '▼'}
          </Button>
        )}
      </div>
      {expanded && capture.ai_result && <AiResultPanel result={capture.ai_result} />}
    </Card>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Event selector dropdown (shared by all tabs)
// ──────────────────────────────────────────────────────────────────────────────
function EventSelector({
  value,
  onChange,
}: {
  value: string;
  onChange: (id: string) => void;
}) {
  const { data: events = [] } = useQuery({
    queryKey: ['events'],
    queryFn: () => listEvents(),
  });

  return (
    <div>
      <label className="block text-textSecondary text-xs mb-1">Link to event (optional)</label>
      <select
        value={value}
        onChange={e => onChange(e.target.value)}
        className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
      >
        <option value="">— No event —</option>
        {events.map(ev => (
          <option key={ev.id} value={ev.id}>
            {ev.title}
          </option>
        ))}
      </select>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Text Note tab
// ──────────────────────────────────────────────────────────────────────────────
function TextNoteTab({ onSuccess }: { onSuccess: () => void }) {
  const [content, setContent] = useState('');
  const [eventId, setEventId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!content.trim()) return;
    setLoading(true);
    setError(null);
    try {
      await createTextNote({ content, event_id: eventId || null });
      setContent('');
      setEventId('');
      onSuccess();
    } catch (err: unknown) {
      setError(apiErrorMessage(err, 'Failed to save note'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <div>
        <label className="block text-textSecondary text-xs mb-1">Note content</label>
        <textarea
          rows={5}
          value={content}
          onChange={e => setContent(e.target.value)}
          className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent resize-none"
          placeholder="Write your note here…"
        />
      </div>
      <EventSelector value={eventId} onChange={setEventId} />
      {error && <p className="text-error text-sm">{error}</p>}
      <Button
        variant="primary"
        onClick={handleSubmit}
        disabled={loading || !content.trim()}
      >
        {loading ? 'Saving…' : 'Save Note'}
      </Button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Link tab
// ──────────────────────────────────────────────────────────────────────────────
function LinkTab({ onSuccess }: { onSuccess: () => void }) {
  const [url, setUrl] = useState('');
  const [title, setTitle] = useState('');
  const [eventId, setEventId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!url.trim()) return;
    setLoading(true);
    setError(null);
    try {
      await saveLink({ url, title: title || null, event_id: eventId || null });
      setUrl('');
      setTitle('');
      setEventId('');
      onSuccess();
    } catch (err: unknown) {
      setError(apiErrorMessage(err, 'Failed to save link'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <div>
        <label className="block text-textSecondary text-xs mb-1">URL</label>
        <input
          type="url"
          value={url}
          onChange={e => setUrl(e.target.value)}
          className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          placeholder="https://…"
        />
      </div>
      <div>
        <label className="block text-textSecondary text-xs mb-1">Title (optional)</label>
        <input
          type="text"
          value={title}
          onChange={e => setTitle(e.target.value)}
          className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          placeholder="Descriptive title"
        />
      </div>
      <EventSelector value={eventId} onChange={setEventId} />
      {error && <p className="text-error text-sm">{error}</p>}
      <Button
        variant="primary"
        onClick={handleSubmit}
        disabled={loading || !url.trim()}
      >
        {loading ? 'Saving…' : 'Save Link'}
      </Button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// File upload tab (Photo/Video OR Document — shared component)
// ──────────────────────────────────────────────────────────────────────────────
function FileUploadTab({
  captureType,
  accept,
  onSuccess,
}: {
  captureType: 'photo' | 'document';
  accept: string;
  onSuccess: () => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [eventId, setEventId] = useState('');
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  async function handleUpload() {
    if (!file) return;
    setLoading(true);
    setError(null);

    try {
      // Step 1 – get presigned upload URL
      setProgress('Preparing upload…');
      const ext = file.name.split('.').pop()?.toLowerCase() ?? '';
      const { upload_url, capture_id, s3_key } = await getUploadUrl({
        capture_type: captureType,
        file_extension: ext,
        content_type: file.type,
        event_id: eventId || null,
      });

      // Step 2 – PUT directly to S3 (no auth header — presigned URL handles auth)
      setProgress('Uploading to storage…');
      await uploadFileToS3(upload_url, file, file.type);

      // Step 3 – register the capture in the backend
      setProgress('Registering capture…');
      await registerCapture({
        capture_id,
        storage_key: s3_key,
        capture_type: captureType,
        event_id: eventId || null,
        mime_type: file.type,
        duration: null,
      });

      setFile(null);
      setEventId('');
      setProgress(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
      onSuccess();
    } catch (err: unknown) {
      setError(apiErrorMessage(err, 'Upload failed'));
      setProgress(null);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <div>
        <label className="block text-textSecondary text-xs mb-1">
          {captureType === 'photo' ? 'Photo or Video' : 'Document'}
        </label>
        <input
          ref={fileInputRef}
          type="file"
          accept={accept}
          onChange={e => setFile(e.target.files?.[0] ?? null)}
          className="block w-full text-textSecondary text-sm
            file:mr-3 file:py-2 file:px-4 file:rounded-lg file:border-0
            file:text-sm file:font-medium file:bg-accent file:text-white
            hover:file:bg-accentHover cursor-pointer"
        />
        {file && (
          <p className="text-textMuted text-xs mt-1">
            {file.name} — {(file.size / 1024 / 1024).toFixed(2)} MB
          </p>
        )}
      </div>
      <EventSelector value={eventId} onChange={setEventId} />
      {progress && (
        <div className="flex items-center gap-2">
          <LoadingSpinner size="sm" />
          <span className="text-textSecondary text-sm">{progress}</span>
        </div>
      )}
      {error && <p className="text-error text-sm">{error}</p>}
      <Button
        variant="primary"
        onClick={handleUpload}
        disabled={loading || !file}
      >
        {loading ? 'Uploading…' : 'Upload'}
      </Button>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Main screen
// ──────────────────────────────────────────────────────────────────────────────
export default function CaptureScreen() {
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<CaptureTab>('note');

  const { data: captures = [], isLoading, error } = useQuery({
    queryKey: ['captures'],
    queryFn: () => listCaptures(),
  });

  // Show most recent 10
  const recent = [...captures]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, 10);

  function onSuccess() {
    queryClient.invalidateQueries({ queryKey: ['captures'] });
  }

  const tabs: { key: CaptureTab; label: string }[] = [
    { key: 'note', label: '📝 Text Note' },
    { key: 'link', label: '🔗 Link' },
    { key: 'photo', label: '📸 Photo / Video' },
    { key: 'document', label: '📄 Document' },
  ];

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-textPrimary text-2xl font-bold">Capture</h1>
        <p className="text-textSecondary text-sm mt-1">
          Save notes, links, photos, and documents — AI will process them in the background.
        </p>
      </div>

      {/* Capture form card */}
      <Card className="space-y-5">
        {/* Tab bar */}
        <div className="flex gap-1 border-b border-border -mx-4 px-4">
          {tabs.map(t => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={[
                'px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px whitespace-nowrap',
                tab === t.key
                  ? 'border-accent text-accent'
                  : 'border-transparent text-textSecondary hover:text-textPrimary',
              ].join(' ')}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* Tab content */}
        <div>
          {tab === 'note' && <TextNoteTab onSuccess={onSuccess} />}
          {tab === 'link' && <LinkTab onSuccess={onSuccess} />}
          {tab === 'photo' && (
            <FileUploadTab
              captureType="photo"
              accept="image/*,video/*"
              onSuccess={onSuccess}
            />
          )}
          {tab === 'document' && (
            <FileUploadTab
              captureType="document"
              accept=".pdf,.doc,.docx,.txt,.md,.pptx,.xlsx,.csv"
              onSuccess={onSuccess}
            />
          )}
        </div>
      </Card>

      {/* Recent captures */}
      <div>
        <h2 className="text-textPrimary text-lg font-semibold mb-3">Recent Captures</h2>
        {isLoading ? (
          <div className="flex justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : error ? (
          <Card className="text-error text-sm">Failed to load captures.</Card>
        ) : recent.length === 0 ? (
          <EmptyState
            icon="📎"
            title="No captures yet"
            subtitle="Your text notes, links, photos, and documents will appear here."
          />
        ) : (
          <div className="space-y-3">
            {recent.map(c => (
              <CaptureCard key={c.id} capture={c} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
