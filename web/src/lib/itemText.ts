/**
 * Text for one entry of a list the AI produced (topics, action items, deadlines...).
 *
 * The backend sometimes returns plain strings and sometimes objects such as
 * { title, due_at }. React cannot render an object as a child (it throws and blanks the
 * whole page), so every list item goes through here first.
 */
export type ListItem =
  | string
  | { title?: string | null; name?: string | null; text?: string | null; due_at?: string | null; deadline_at?: string | null };

function shortDate(iso: string): string | null {
  // "2026-10-20" must stay Oct 20 in every timezone, so build it from its parts.
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  const date = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(iso);
  return Number.isNaN(date.getTime())
    ? null
    : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

export function itemText(item: unknown): string {
  if (item === null || item === undefined) return '';
  if (typeof item === 'string') return item;
  if (typeof item === 'number' || typeof item === 'boolean') return String(item);
  if (typeof item === 'object') {
    const o = item as Record<string, unknown>;
    const label = [o.title, o.name, o.text].find((v) => typeof v === 'string' && v.trim()) as string | undefined;
    const dueRaw = [o.due_at, o.deadline_at].find((v) => typeof v === 'string' && v) as string | undefined;
    const due = dueRaw ? shortDate(dueRaw) : null;
    if (label) return due ? `${label} (due ${due})` : label;
  }
  return '';
}
