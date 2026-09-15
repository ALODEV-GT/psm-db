-- Migration: event_checklist_timeline
-- event_checklist tracks the 4-item pre-flight checklist per event (design.md
-- D4: no trigger prepopulates rows — Express inserts them, since events has
-- no non-Express write path). timeline_notes is the free-form event-day log.

create table public.event_checklist (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  item public.checklist_item not null,
  is_completed boolean not null default false,
  completed_at timestamptz,
  completed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint event_checklist_event_id_item_uq unique (event_id, item),
  constraint event_checklist_completion_ck check (is_completed = (completed_at is not null))
);

create index event_checklist_event_id_idx on public.event_checklist (event_id);

create trigger set_event_checklist_updated_at
  before update on public.event_checklist
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.event_checklist enable row level security;
revoke all on public.event_checklist from anon, authenticated;

create table public.timeline_notes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  body text not null,
  elapsed_seconds integer not null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint timeline_notes_body_ck check (btrim(body) <> ''),
  constraint timeline_notes_elapsed_seconds_ck check (elapsed_seconds >= 0)
);

create index timeline_notes_event_id_elapsed_seconds_idx on public.timeline_notes (event_id, elapsed_seconds);

create trigger set_timeline_notes_updated_at
  before update on public.timeline_notes
  for each row
  execute function public.set_updated_at();

alter table public.timeline_notes enable row level security;
revoke all on public.timeline_notes from anon, authenticated;
