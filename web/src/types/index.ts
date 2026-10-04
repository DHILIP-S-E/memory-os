import type { ListItem } from '../lib/itemText';
// ---------------------------------------------------------------------------
// Reminder
// ---------------------------------------------------------------------------
export interface Reminder {
  id: string;
  user_id: string;
  title: string;
  description: string | null;
  reminder_type: 'time' | 'deadline' | 'recurring' | 'follow-up' | 'multi-stage';
  scheduled_at: string | null; // ISO 8601
  timezone: string;
  priority: 'low' | 'medium' | 'high' | 'critical';
  status: 'active' | 'completed' | 'snoozed' | 'cancelled';
  alarm_enabled: boolean;
  notification_enabled: boolean;
  recurrence_rule: string | null;
  source: 'manual' | 'ai' | 'event';
  context_id: string | null;
  depends_on_id: string | null;
  offsets: string[];
  created_at: string;
  updated_at: string;
}

export interface ReminderCreate {
  title: string;
  description?: string | null;
  reminder_type: Reminder['reminder_type'];
  scheduled_at?: string | null;
  timezone?: string;
  priority?: Reminder['priority'];
  alarm_enabled?: boolean;
  notification_enabled?: boolean;
  recurrence_rule?: string | null;
  context_id?: string | null;
  depends_on_id?: string | null;
  offsets?: string[];
}

export interface ReminderUpdate {
  title?: string;
  description?: string | null;
  reminder_type?: Reminder['reminder_type'];
  scheduled_at?: string | null;
  timezone?: string;
  priority?: Reminder['priority'];
  status?: Reminder['status'];
  alarm_enabled?: boolean;
  notification_enabled?: boolean;
  recurrence_rule?: string | null;
  offsets?: string[];
}

// ---------------------------------------------------------------------------
// Event
// ---------------------------------------------------------------------------
export interface EventDeadline {
  id: string;
  event_id: string;
  user_id: string;
  title: string;
  deadline_type: string;
  deadline_at: string;
  status: string;
  created_at: string;
}

export interface DeadlineIn {
  title: string;
  deadline_type: string;
  deadline_at: string;
}

export interface Event {
  id: string;
  user_id: string;
  title: string;
  description: string | null;
  event_type:
    | 'hackathon'
    | 'conference'
    | 'workshop'
    | 'webinar'
    | 'meetup'
    | 'meeting'
    | 'appointment'
    | 'deadline'
    | 'custom';
  start_at: string;
  end_at: string | null;
  timezone: string;
  location: string | null;
  is_virtual: boolean;
  event_url: string | null;
  organizer: string | null;
  registration_url: string | null;
  status: 'draft' | 'registered' | 'upcoming' | 'active' | 'attended' | 'completed';
  summary_id: string | null;
  photo_count: number;
  voice_note_count: number;
  document_count: number;
  deadlines: EventDeadline[];
  created_at: string;
  updated_at: string;
}

export interface EventCreate {
  title: string;
  description?: string | null;
  event_type: Event['event_type'];
  start_at: string;
  end_at?: string | null;
  timezone?: string;
  location?: string | null;
  is_virtual?: boolean;
  event_url?: string | null;
  organizer?: string | null;
  registration_url?: string | null;
  deadlines?: DeadlineIn[];
}

export interface EventUpdate {
  title?: string;
  description?: string | null;
  event_type?: Event['event_type'];
  start_at?: string;
  end_at?: string | null;
  timezone?: string;
  location?: string | null;
  is_virtual?: boolean;
  event_url?: string | null;
  organizer?: string | null;
  registration_url?: string | null;
  status?: Event['status'];
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------
export interface AIResult {
  summary: string;
  topics: string[];
  key_points: string[];
  actions: string[];
}

export interface Capture {
  id: string;
  user_id: string;
  event_id: string | null;
  capture_type: 'photo' | 'voice' | 'note' | 'document' | 'link';
  storage_key: string | null;
  mime_type: string | null;
  duration: number | null;
  transcription: string | null;
  content: string | null;
  processing_status: 'uploaded' | 'queued' | 'processing' | 'processed' | 'failed';
  ai_result: AIResult | null;
  created_at: string;
  updated_at: string;
}

export interface UploadUrlRequest {
  capture_type: 'photo' | 'voice' | 'document';
  file_extension: string;   // e.g. 'jpg', 'pdf', 'm4a'
  content_type: string;     // e.g. 'image/jpeg', 'application/pdf'
  event_id?: string | null;
}

export interface RegisterCaptureRequest {
  capture_id: string;
  storage_key: string;
  capture_type: 'photo' | 'voice' | 'document';
  event_id?: string | null;
  mime_type?: string | null;
  duration?: number | null;
}

export interface TextNoteRequest {
  event_id?: string | null;
  content: string;
}

export interface LinkRequest {
  event_id?: string | null;
  url: string;
  title?: string | null;
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------
export interface MemoryDocument {
  id: string;
  user_id: string;
  event_id: string | null;
  event_title: string | null;
  overview: string | null;
  key_topics: string[];
  key_takeaways: string[];
  things_learned: string[];
  important_people: string[];
  resources: string[];
  links: string[];
  action_items: ListItem[];
  deadlines: ListItem[];
  decisions: string[];
  event_date: string;
  created_at: string;
  updated_at: string;
}

export interface AskRequest {
  question: string;
}

export interface AskResponse {
  question: string;
  answer: string;
  sources: Array<{
    event_title: string;
    event_id: string | null;
  }>;
}

// ---------------------------------------------------------------------------
// AI helpers
// ---------------------------------------------------------------------------
export interface ParseReminderResponse {
  title: string;
  description?: string | null;
  reminder_type?: string;
  scheduled_at?: string | null;
  timezone?: string;
  priority?: string;
  recurrence_rule?: string | null;
  offsets?: string[];
}

export interface ExtractEventResponse {
  title: string;
  description?: string | null;
  event_type?: string;
  start_at?: string | null;
  end_at?: string | null;
  timezone?: string;
  location?: string | null;
  is_virtual?: boolean;
  event_url?: string | null;
  organizer?: string | null;
  registration_url?: string | null;
  deadlines?: DeadlineIn[];
}
