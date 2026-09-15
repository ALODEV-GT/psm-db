-- Migration: events
-- The core booking record. client_id/event_type_id are protected with
-- ON DELETE RESTRICT: a lookup or client with existing events cannot be
-- deleted out from under history (deactivate via is_active instead).
-- No event_date column (design.md D8) — schedule is derived from
-- event_services in migration 10's reporting views, since PRD rule 2
-- allows two livestreams on different dates within the same event.

create table public.events (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id) on delete restrict,
  event_type_id uuid not null references public.event_types (id) on delete restrict,
  location text not null,
  notes text,
  deposit_amount numeric(12, 2) not null default 0,
  status public.event_status not null default 'programado',
  title text,
  subtitle text,
  crawl text,
  transmission_started_at timestamptz,
  transmission_ended_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint events_deposit_amount_ck check (deposit_amount >= 0),
  constraint events_transmission_window_ck check (
    transmission_ended_at is null
    or (transmission_started_at is not null and transmission_ended_at > transmission_started_at)
  )
);

create index events_client_id_idx on public.events (client_id);
create index events_event_type_id_idx on public.events (event_type_id);
create index events_status_idx on public.events (status);

create trigger set_events_updated_at
  before update on public.events
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.events enable row level security;
revoke all on public.events from anon, authenticated;
