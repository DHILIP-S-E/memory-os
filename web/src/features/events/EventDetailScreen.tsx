import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import EmptyState from '../../components/ui/EmptyState';
import {
  getEvent,
  updateEvent,
  addDeadline,
  previewReminderPolicy,
  applyReminderPolicy,
  generateSummary,
  getEventSummary,
} from './eventsApi';
import { listCaptures } from '../capture/capturesApi';
import type { Event, EventUpdate, DeadlineIn, MemoryDocument, Capture } from '../../types/index';
import { itemText, type ListItem } from '../../lib/itemText';

type Tab = 'overview' | 'captures' | 'deadlines' | 'reminders' | 'summary';

// ---------------------------------------------------------------------------
// Root screen
// ---------------------------------------------------------------------------
export default function EventDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<Tab>('overview');

  const { data: event, isLoading, error } = useQuery({
    queryKey: ['events', id],
    queryFn: () => getEvent(id!),
    enabled: !!id,
  });

  if (isLoading) {
    return (
      <div className="flex justify-center py-20">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !event) {
    return (
      <Card className="text-error text-sm">
        Failed to load event.{' '}
        <button className="underline text-textSecondary ml-2" onClick={() => navigate('/events')}>
          Back to Events
        </button>
      </Card>
    );
  }

  const tabs: { key: Tab; label: string }[] = [
    { key: 'overview', label: 'Overview' },
    { key: 'captures', label: 'Captures' },
    { key: 'deadlines', label: 'Deadlines' },
    { key: 'reminders', label: 'Reminders' },
    { key: 'summary', label: 'Summary' },
  ];

  return (
    <div className="space-y-6">
      {/* Back link */}
      <button
        onClick={() => navigate('/events')}
        className="text-textMuted text-sm hover:text-textPrimary transition-colors"
      >
        ← Back to Events
      </button>

      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-start gap-3 flex-wrap">
          <h1 className="text-textPrimary text-2xl font-bold flex-1">{event.title}</h1>
          <Badge label={event.event_type} />
          <Badge label={event.status} />
        </div>
        <div className="flex flex-wrap gap-4 text-textMuted text-sm">
          <span>📅 {format(new Date(event.start_at), 'PPp')}</span>
          {event.end_at && <span>→ {format(new Date(event.end_at), 'PPp')}</span>}
          {event.is_virtual ? (
            <span className="bg-indigo-900/50 text-indigo-300 px-2 py-0.5 rounded-full text-xs">Virtual</span>
          ) : event.location ? (
            <span>📍 {event.location}</span>
          ) : null}
          {event.organizer && <span>👤 {event.organizer}</span>}
          {event.event_url && (
            <a
              href={event.event_url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-accent hover:underline"
            >
              🔗 Event link
            </a>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-border">
        {tabs.map(t => (
          <button
            key={t.key}
            onClick={() => setActiveTab(t.key)}
            className={[
              'px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px',
              activeTab === t.key
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
        {activeTab === 'overview' && <OverviewTab event={event} />}
        {activeTab === 'captures' && <CapturesTab eventId={event.id} />}
        {activeTab === 'deadlines' && <DeadlinesTab event={event} />}
        {activeTab === 'reminders' && <RemindersTab eventId={event.id} />}
        {activeTab === 'summary' && <SummaryTab event={event} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Overview Tab
// ---------------------------------------------------------------------------
function OverviewTab({ event }: { event: Event }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<EventUpdate>({});
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  function startEdit() {
    setForm({
      title: event.title,
      description: event.description,
      event_type: event.event_type,
      start_at: event.start_at,
      end_at: event.end_at,
      timezone: event.timezone,
      location: event.location,
      is_virtual: event.is_virtual,
      event_url: event.event_url,
      organizer: event.organizer,
      registration_url: event.registration_url,
      status: event.status,
    });
    setEditing(true);
  }

  async function handleSave() {
    setEditError(null);
    setSaving(true);
    try {
      await updateEvent(event.id, form);
      queryClient.invalidateQueries({ queryKey: ['events', event.id] });
      queryClient.invalidateQueries({ queryKey: ['events'] });
      setEditing(false);
    } catch (err: unknown) {
      setEditError(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  function setF<K extends keyof EventUpdate>(key: K, value: EventUpdate[K]) {
    setForm(prev => ({ ...prev, [key]: value }));
  }

  if (!editing) {
    return (
      <div className="space-y-4">
        <div className="flex justify-end">
          <Button variant="secondary" size="sm" onClick={startEdit}>Edit</Button>
        </div>
        <dl className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Field label="Title" value={event.title} />
          <Field label="Type" value={event.event_type} />
          <Field label="Status" value={event.status} />
          <Field label="Timezone" value={event.timezone} />
          <Field label="Start" value={format(new Date(event.start_at), 'PPpp')} />
          <Field label="End" value={event.end_at ? format(new Date(event.end_at), 'PPpp') : '—'} />
          <Field label="Location" value={event.location ?? '—'} />
          <Field label="Virtual" value={event.is_virtual ? 'Yes' : 'No'} />
          <Field label="Organizer" value={event.organizer ?? '—'} />
          <Field label="Event URL" value={event.event_url ?? '—'} />
          <Field label="Registration URL" value={event.registration_url ?? '—'} />
          {event.description && (
            <div className="col-span-2">
              <dt className="text-textMuted text-xs font-medium uppercase mb-1">Description</dt>
              <dd className="text-textPrimary text-sm">{event.description}</dd>
            </div>
          )}
        </dl>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {editError && (
        <div className="bg-red-900/40 border border-red-700 text-red-300 rounded-lg px-4 py-3 text-sm">
          {editError}
        </div>
      )}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <EditField label="Title" value={form.title ?? ''} onChange={v => setF('title', v)} />
        <div>
          <label className="block text-textMuted text-xs font-medium uppercase mb-1">Type</label>
          <select
            value={form.event_type ?? 'meeting'}
            onChange={e => setF('event_type', e.target.value as EventUpdate['event_type'])}
            className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          >
            {(['hackathon','conference','workshop','webinar','meetup','meeting','appointment','deadline','custom'] as const).map(t => (
              <option key={t} value={t}>{t.charAt(0).toUpperCase() + t.slice(1)}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-textMuted text-xs font-medium uppercase mb-1">Status</label>
          <select
            value={form.status ?? event.status}
            onChange={e => setF('status', e.target.value as EventUpdate['status'])}
            className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          >
            {(['draft','registered','upcoming','active','attended','completed'] as const).map(s => (
              <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
            ))}
          </select>
        </div>
        <EditField label="Timezone" value={form.timezone ?? ''} onChange={v => setF('timezone', v)} />
        <div>
          <label className="block text-textMuted text-xs font-medium uppercase mb-1">Start At</label>
          <input
            type="datetime-local"
            value={form.start_at ? form.start_at.slice(0, 16) : ''}
            onChange={e => setF('start_at', e.target.value ? e.target.value + ':00' : '')}
            className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          />
        </div>
        <div>
          <label className="block text-textMuted text-xs font-medium uppercase mb-1">End At</label>
          <input
            type="datetime-local"
            value={form.end_at ? form.end_at.slice(0, 16) : ''}
            onChange={e => setF('end_at', e.target.value ? e.target.value + ':00' : null)}
            className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          />
        </div>
        <EditField label="Location" value={form.location ?? ''} onChange={v => setF('location', v || null)} />
        <div className="flex items-end pb-2">
          <label className="flex items-center gap-2 cursor-pointer select-none text-sm text-textSecondary">
            <input
              type="checkbox"
              checked={form.is_virtual ?? false}
              onChange={e => setF('is_virtual', e.target.checked)}
              className="w-4 h-4 accent-accent"
            />
            Virtual
          </label>
        </div>
        <EditField label="Organizer" value={form.organizer ?? ''} onChange={v => setF('organizer', v || null)} />
        <EditField label="Event URL" value={form.event_url ?? ''} onChange={v => setF('event_url', v || null)} />
        <EditField label="Registration URL" value={form.registration_url ?? ''} onChange={v => setF('registration_url', v || null)} />
      </div>
      <div>
        <label className="block text-textMuted text-xs font-medium uppercase mb-1">Description</label>
        <textarea
          rows={3}
          value={form.description ?? ''}
          onChange={e => setF('description', e.target.value || null)}
          className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent resize-none"
        />
      </div>
      <div className="flex gap-3">
        <Button variant="primary" size="sm" onClick={handleSave} disabled={saving}>
          {saving ? 'Saving…' : 'Save'}
        </Button>
        <Button variant="secondary" size="sm" onClick={() => setEditing(false)}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-textMuted text-xs font-medium uppercase mb-0.5">{label}</dt>
      <dd className="text-textPrimary text-sm">{value}</dd>
    </div>
  );
}

function EditField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div>
      <label className="block text-textMuted text-xs font-medium uppercase mb-1">{label}</label>
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Captures Tab
// ---------------------------------------------------------------------------
function CapturesTab({ eventId }: { eventId: string }) {
  const { data: captures = [], isLoading, error } = useQuery({
    queryKey: ['captures', { event_id: eventId }],
    queryFn: () => listCaptures({ event_id: eventId }),
  });

  if (isLoading) return <div className="flex justify-center py-10"><LoadingSpinner /></div>;
  if (error) return <Card className="text-error text-sm">Failed to load captures.</Card>;
  if (captures.length === 0) {
    return (
      <EmptyState
        icon="📸"
        title="No captures yet"
        subtitle="Use the Capture screen to add photos, notes, or documents to this event."
      />
    );
  }

  return (
    <div className="space-y-3">
      {captures.map(c => <CaptureRow key={c.id} capture={c} />)}
    </div>
  );
}

function CaptureRow({ capture: c }: { capture: Capture }) {
  const typeIcon: Record<string, string> = {
    photo: '📷', voice: '🎤', note: '📝', document: '📄', link: '🔗',
  };
  return (
    <Card variant="card" className="space-y-1">
      <div className="flex items-center gap-2">
        <span className="text-xl">{typeIcon[c.capture_type] ?? '📎'}</span>
        <span className="text-textPrimary text-sm font-medium flex-1 truncate">
          {c.content ?? c.storage_key ?? c.id}
        </span>
        <Badge label={c.processing_status} />
      </div>
      {c.ai_result?.summary && (
        <p className="text-textMuted text-xs pl-7 line-clamp-2">{c.ai_result.summary}</p>
      )}
      <p className="text-textMuted text-xs pl-7">
        {format(new Date(c.created_at), 'PPp')}
      </p>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Deadlines Tab
// ---------------------------------------------------------------------------
function DeadlinesTab({ event }: { event: Event }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<DeadlineIn>({ title: '', deadline_type: 'submission', deadline_at: '' });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!form.title || !form.deadline_at) return;
    setErr(null);
    setSaving(true);
    try {
      await addDeadline(event.id, form);
      queryClient.invalidateQueries({ queryKey: ['events', event.id] });
      setForm({ title: '', deadline_type: 'submission', deadline_at: '' });
    } catch (error: unknown) {
      setErr(error instanceof Error ? error.message : 'Failed to add deadline');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-4">
      {event.deadlines.length === 0 ? (
        <p className="text-textMuted text-sm">No deadlines yet.</p>
      ) : (
        <div className="space-y-2">
          {event.deadlines.map(d => (
            <Card key={d.id} variant="card" className="flex items-center gap-3">
              <div className="flex-1">
                <p className="text-textPrimary text-sm font-medium">{d.title}</p>
                <p className="text-textMuted text-xs">
                  {d.deadline_type} · {format(new Date(d.deadline_at), 'PPp')}
                </p>
              </div>
              <Badge label={d.status} />
            </Card>
          ))}
        </div>
      )}

      <div className="border-t border-border pt-4">
        <h3 className="text-textPrimary text-sm font-medium mb-3">Add Deadline</h3>
        {err && <p className="text-error text-sm mb-2">{err}</p>}
        <form onSubmit={handleAdd} className="flex gap-2 flex-wrap">
          <input
            type="text"
            value={form.title}
            onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
            placeholder="Deadline title"
            required
            className="flex-1 min-w-40 bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          />
          <input
            type="text"
            value={form.deadline_type}
            onChange={e => setForm(f => ({ ...f, deadline_type: e.target.value }))}
            placeholder="Type (e.g. submission)"
            className="w-36 bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          />
          <input
            type="datetime-local"
            value={form.deadline_at ? form.deadline_at.slice(0, 16) : ''}
            onChange={e => setForm(f => ({ ...f, deadline_at: e.target.value ? e.target.value + ':00' : '' }))}
            required
            className="w-44 bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          />
          <Button type="submit" variant="primary" size="sm" disabled={saving}>
            {saving ? 'Adding…' : 'Add'}
          </Button>
        </form>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Reminders Tab
// ---------------------------------------------------------------------------
interface PolicyReminder {
  title?: string;
  scheduled_at?: string;
  priority?: string;
  reminder_type?: string;
  [key: string]: unknown;
}

function RemindersTab({ eventId }: { eventId: string }) {
  const [policy, setPolicy] = useState<PolicyReminder[] | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [applying, setApplying] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [applyError, setApplyError] = useState<string | null>(null);
  const [applied, setApplied] = useState(false);

  async function handlePreview() {
    setPreviewError(null);
    setPreviewing(true);
    try {
      const result = await previewReminderPolicy(eventId);
      setPolicy(result as PolicyReminder[]);
      setApplied(false);
    } catch (err: unknown) {
      setPreviewError(err instanceof Error ? err.message : 'Failed to load policy');
    } finally {
      setPreviewing(false);
    }
  }

  async function handleApply() {
    setApplyError(null);
    setApplying(true);
    try {
      await applyReminderPolicy(eventId);
      setApplied(true);
    } catch (err: unknown) {
      setApplyError(err instanceof Error ? err.message : 'Failed to apply policy');
    } finally {
      setApplying(false);
    }
  }

  return (
    <div className="space-y-4">
      <p className="text-textMuted text-sm">
        Preview the AI-suggested reminder policy for this event, then apply it to create reminders.
      </p>

      {!policy && (
        <Button variant="primary" size="sm" onClick={handlePreview} disabled={previewing}>
          {previewing ? 'Loading…' : 'Preview Reminder Policy'}
        </Button>
      )}

      {previewError && <p className="text-error text-sm">{previewError}</p>}

      {policy && policy.length === 0 && (
        <p className="text-textMuted text-sm">No reminders suggested by policy.</p>
      )}

      {policy && policy.length > 0 && (
        <div className="space-y-3">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-textMuted text-xs uppercase border-b border-border">
                  <th className="text-left py-2 pr-4">Title</th>
                  <th className="text-left py-2 pr-4">Type</th>
                  <th className="text-left py-2 pr-4">Priority</th>
                  <th className="text-left py-2">Scheduled At</th>
                </tr>
              </thead>
              <tbody>
                {policy.map((p, i) => (
                  <tr key={i} className="border-b border-border/50">
                    <td className="py-2 pr-4 text-textPrimary">{p.title ?? '—'}</td>
                    <td className="py-2 pr-4">
                      {p.reminder_type ? <Badge label={p.reminder_type} /> : '—'}
                    </td>
                    <td className="py-2 pr-4">
                      {p.priority ? <Badge label={p.priority} /> : '—'}
                    </td>
                    <td className="py-2 text-textMuted">
                      {p.scheduled_at ? format(new Date(p.scheduled_at), 'PPp') : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {applied ? (
            <p className="text-success text-sm">✓ Policy applied — reminders created.</p>
          ) : (
            <>
              {applyError && <p className="text-error text-sm">{applyError}</p>}
              <div className="flex gap-3">
                <Button variant="primary" size="sm" onClick={handleApply} disabled={applying}>
                  {applying ? 'Applying…' : 'Apply Policy'}
                </Button>
                <Button variant="ghost" size="sm" onClick={() => { setPolicy(null); setApplied(false); }}>
                  Reset
                </Button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Summary Tab
// ---------------------------------------------------------------------------
function SummaryTab({ event }: { event: Event }) {
  const queryClient = useQueryClient();
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState<string | null>(null);
  const [localSummary, setLocalSummary] = useState<MemoryDocument | null>(null);

  const { data: existingSummary, isLoading: loadingSummary } = useQuery({
    queryKey: ['event-summary', event.id],
    queryFn: () => getEventSummary(event.id),
    enabled: !!event.summary_id,
    retry: false,
  });

  const summary = localSummary ?? existingSummary;

  async function handleGenerate() {
    setGenError(null);
    setGenerating(true);
    try {
      const result = await generateSummary(event.id);
      setLocalSummary(result);
      queryClient.invalidateQueries({ queryKey: ['events', event.id] });
      queryClient.invalidateQueries({ queryKey: ['event-summary', event.id] });
    } catch (err: unknown) {
      setGenError(err instanceof Error ? err.message : 'Failed to generate summary');
    } finally {
      setGenerating(false);
    }
  }

  if (loadingSummary) {
    return <div className="flex justify-center py-10"><LoadingSpinner /></div>;
  }

  if (!summary) {
    return (
      <div className="space-y-3">
        <p className="text-textMuted text-sm">No summary yet. Generate an AI summary from all event captures.</p>
        {genError && <p className="text-error text-sm">{genError}</p>}
        <Button variant="primary" onClick={handleGenerate} disabled={generating}>
          {generating ? (
            <span className="flex items-center gap-2">
              <LoadingSpinner size="sm" /> Generating…
            </span>
          ) : (
            '✨ Generate AI Summary'
          )}
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* Overview */}
      {summary.overview && (
        <Card variant="card">
          <h3 className="text-textSecondary text-xs font-medium uppercase mb-2">Overview</h3>
          <p className="text-textPrimary text-sm leading-relaxed">{summary.overview}</p>
        </Card>
      )}

      {/* Key topics */}
      {summary.key_topics.length > 0 && (
        <div>
          <h3 className="text-textSecondary text-xs font-medium uppercase mb-2">Key Topics</h3>
          <div className="flex flex-wrap gap-2">
            {summary.key_topics.map((t, i) => (
              <span key={i} className="bg-indigo-900/50 text-indigo-300 px-3 py-1 rounded-full text-xs">
                {t}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Key takeaways */}
      {summary.key_takeaways.length > 0 && (
        <SummaryList title="Key Takeaways" items={summary.key_takeaways} />
      )}

      {/* Action items */}
      {summary.action_items.length > 0 && (
        <SummaryList title="Action Items" items={summary.action_items} icon="✅" />
      )}

      {/* Decisions */}
      {summary.decisions.length > 0 && (
        <SummaryList title="Decisions" items={summary.decisions} icon="🔑" />
      )}

      {/* Important people */}
      {summary.important_people.length > 0 && (
        <SummaryList title="Important People" items={summary.important_people} icon="👤" />
      )}

      {/* Resources */}
      {summary.resources.length > 0 && (
        <SummaryList title="Resources" items={summary.resources} icon="📎" />
      )}

      <div className="border-t border-border pt-4">
        {genError && <p className="text-error text-sm mb-2">{genError}</p>}
        <Button variant="secondary" size="sm" onClick={handleGenerate} disabled={generating}>
          {generating ? 'Regenerating…' : '↻ Regenerate Summary'}
        </Button>
      </div>
    </div>
  );
}

function SummaryList({ title, items, icon }: { title: string; items: ListItem[]; icon?: string }) {
  return (
    <div>
      <h3 className="text-textSecondary text-xs font-medium uppercase mb-2">{title}</h3>
      <ul className="space-y-1">
        {items.map((item, i) => (
          <li key={i} className="text-textPrimary text-sm flex gap-2">
            <span className="text-textMuted shrink-0">{icon ?? '•'}</span>
            <span>{itemText(item)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
