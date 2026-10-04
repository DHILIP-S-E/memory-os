import { useState, useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { format } from 'date-fns';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import EmptyState from '../../components/ui/EmptyState';
import LoadingSpinner from '../../components/ui/LoadingSpinner';
import { listMemory, searchMemory, askMemory } from './memoryApi';
import type { AskResponse, MemoryDocument } from '../../types/index';
import { itemText, type ListItem } from '../../lib/itemText';

// ──────────────────────────────────────────────────────────────────────────────
// Ask zone
// ──────────────────────────────────────────────────────────────────────────────
function AskZone() {
  const [question, setQuestion] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<AskResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleAsk() {
    if (!question.trim()) return;
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const res = await askMemory(question);
      setResult(res);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to get answer');
    } finally {
      setLoading(false);
    }
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') void handleAsk();
  }

  return (
    <Card className="space-y-4">
      <h2 className="text-textPrimary text-lg font-semibold">Ask your memory</h2>
      <div className="flex gap-3">
        <input
          type="text"
          value={question}
          onChange={e => setQuestion(e.target.value)}
          onKeyDown={handleKeyDown}
          className="flex-1 bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
          placeholder="What did I learn at the AWS conference? Who did I meet last month?"
          disabled={loading}
        />
        <Button
          variant="primary"
          onClick={() => void handleAsk()}
          disabled={loading || !question.trim()}
        >
          {loading ? <LoadingSpinner size="sm" /> : 'Ask'}
        </Button>
      </div>

      {error && <p className="text-error text-sm">{error}</p>}

      {result && (
        <div className="bg-card rounded-xl p-4 space-y-3 border border-border">
          <p className="text-textSecondary text-xs font-medium uppercase tracking-wide">Answer</p>
          <p className="text-textPrimary leading-relaxed">{result.answer}</p>

          {result.sources.length > 0 && (
            <div>
              <p className="text-textMuted text-xs mb-2">Sources</p>
              <div className="flex flex-wrap gap-2">
                {result.sources.map((src, i) => (
                  src.event_id ? (
                    <Link
                      key={i}
                      to={`/events/${src.event_id}`}
                      className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-indigo-900 text-indigo-200 hover:bg-indigo-800 transition-colors"
                    >
                      📎 {src.event_title}
                    </Link>
                  ) : (
                    <span
                      key={i}
                      className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-surface text-textSecondary border border-border"
                    >
                      📎 {src.event_title}
                    </span>
                  )
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Search zone
// ──────────────────────────────────────────────────────────────────────────────
function SearchZone() {
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setDebouncedQuery(query), 400);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [query]);

  const { data: results = [], isLoading, error } = useQuery({
    queryKey: ['memory', 'search', debouncedQuery],
    queryFn: () => searchMemory(debouncedQuery),
    enabled: debouncedQuery.trim().length > 0,
  });

  return (
    <div className="space-y-3">
      <h2 className="text-textPrimary text-lg font-semibold">Search memories</h2>
      <input
        type="text"
        value={query}
        onChange={e => setQuery(e.target.value)}
        className="w-full bg-card border border-border rounded-lg px-3 py-2 text-textPrimary text-sm focus:outline-none focus:ring-1 focus:ring-accent"
        placeholder="Search by keyword, topic, or person…"
      />

      {debouncedQuery.trim().length > 0 && (
        <div>
          {isLoading ? (
            <div className="flex justify-center py-6">
              <LoadingSpinner size="md" />
            </div>
          ) : error ? (
            <p className="text-error text-sm">Search failed.</p>
          ) : results.length === 0 ? (
            <p className="text-textMuted text-sm py-4">No memories matched "{debouncedQuery}".</p>
          ) : (
            <div className="space-y-3">
              {results.map(doc => (
                <MemoryCard key={doc.id} doc={doc} />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Memory document card
// ──────────────────────────────────────────────────────────────────────────────
function MemoryCard({ doc }: { doc: MemoryDocument }) {
  const [expanded, setExpanded] = useState(false);

  const topicChips = doc.key_topics.slice(0, 5);

  function formatDate(dateStr: string) {
    try {
      return format(new Date(dateStr), 'PPP');
    } catch {
      return dateStr;
    }
  }

  return (
    <Card variant="card" className="space-y-2">
      {/* Header row */}
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="text-textPrimary font-semibold">
              {doc.event_title ?? 'Untitled memory'}
            </h3>
            {doc.event_id && (
              <Link
                to={`/events/${doc.event_id}`}
                className="text-xs text-accent hover:text-accentHover transition-colors"
              >
                View event →
              </Link>
            )}
          </div>
          <p className="text-textMuted text-xs mt-0.5">{formatDate(doc.event_date)}</p>
        </div>
        <Button variant="ghost" size="sm" onClick={() => setExpanded(v => !v)}>
          {expanded ? '▲' : '▼'}
        </Button>
      </div>

      {/* Overview (2-line clamp) */}
      {doc.overview && (
        <p
          className={[
            'text-textSecondary text-sm',
            expanded ? '' : 'line-clamp-2',
          ].join(' ')}
        >
          {doc.overview}
        </p>
      )}

      {/* Topic chips */}
      {topicChips.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {topicChips.map((t, i) => (
            <Badge key={i} label={t} />
          ))}
        </div>
      )}

      {/* Expanded detail */}
      {expanded && (
        <div className="pt-3 border-t border-border space-y-4 text-sm">
          {doc.key_takeaways.length > 0 && (
            <DetailList title="Key Takeaways" items={doc.key_takeaways} />
          )}
          {doc.things_learned.length > 0 && (
            <DetailList title="Things Learned" items={doc.things_learned} />
          )}
          {doc.important_people.length > 0 && (
            <DetailList title="Important People" items={doc.important_people} />
          )}
          {doc.action_items.length > 0 && (
            <DetailList title="Action Items" items={doc.action_items} />
          )}
          {doc.decisions.length > 0 && (
            <DetailList title="Decisions" items={doc.decisions} />
          )}
          {doc.resources.length > 0 && (
            <DetailList title="Resources" items={doc.resources} />
          )}
          {doc.links.length > 0 && (
            <div>
              <p className="text-textMuted text-xs font-medium uppercase tracking-wide mb-1">Links</p>
              <ul className="space-y-1">
                {doc.links.map((link, i) => (
                  <li key={i}>
                    <a
                      href={link}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-accent hover:text-accentHover text-xs truncate block"
                    >
                      {link}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}

function DetailList({ title, items }: { title: string; items: ListItem[] }) {
  return (
    <div>
      <p className="text-textMuted text-xs font-medium uppercase tracking-wide mb-1">{title}</p>
      <ul className="list-disc list-inside text-textSecondary space-y-0.5">
        {items.map((item, i) => <li key={i}>{itemText(item)}</li>)}
      </ul>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Main screen
// ──────────────────────────────────────────────────────────────────────────────
export default function MemoryScreen() {
  const { data: memories = [], isLoading, error } = useQuery({
    queryKey: ['memory'],
    queryFn: listMemory,
  });

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-textPrimary text-2xl font-bold">Memory</h1>
        <p className="text-textSecondary text-sm mt-1">
          Ask questions, search, and explore everything you've captured.
        </p>
      </div>

      {/* Ask zone */}
      <AskZone />

      {/* Search zone */}
      <SearchZone />

      {/* All memories */}
      <div>
        <h2 className="text-textPrimary text-lg font-semibold mb-3">All Memories</h2>
        {isLoading ? (
          <div className="flex justify-center py-12">
            <LoadingSpinner size="lg" />
          </div>
        ) : error ? (
          <Card className="text-error text-sm">Failed to load memories.</Card>
        ) : memories.length === 0 ? (
          <EmptyState
            icon="🧠"
            title="No memories yet"
            subtitle="Generate summaries for your events and they'll appear here."
          />
        ) : (
          <div className="space-y-3">
            {memories.map(doc => (
              <MemoryCard key={doc.id} doc={doc} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
