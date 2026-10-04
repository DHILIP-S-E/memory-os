import { describe, expect, it } from 'vitest';
import { itemText } from './itemText';

describe('itemText', () => {
  it('passes plain strings through', () => {
    expect(itemText('Bedrock Agents')).toBe('Bedrock Agents');
  });

  it('renders an action item object with its due date (the case that crashed the page)', () => {
    expect(itemText({ title: 'Submit the prototype', due_at: '2026-10-20' })).toBe('Submit the prototype (due Oct 20)');
  });

  it('keeps a date-only value on the same day in any timezone', () => {
    expect(itemText({ title: 'x', due_at: '2026-01-01' })).toBe('x (due Jan 1)');
  });

  it('omits the date when there is none or it is not valid', () => {
    expect(itemText({ title: 'Follow up', due_at: null })).toBe('Follow up');
    expect(itemText({ title: 'Follow up', due_at: 'null' })).toBe('Follow up');
    expect(itemText({ title: 'Follow up', due_at: 'next week' })).toBe('Follow up');
  });

  it('accepts name/text labels and deadline_at', () => {
    expect(itemText({ name: 'Register', deadline_at: '2026-10-10T23:59:00+00:00' })).toBe('Register (due Oct 10)');
    expect(itemText({ text: 'a note' })).toBe('a note');
  });

  it('never returns an object, whatever the input', () => {
    for (const weird of [null, undefined, 42, true, {}, [], [1, 2], { title: 5 }, { a: { b: 1 } }]) {
      expect(typeof itemText(weird)).toBe('string');
    }
  });
});
