-- Migration: event_closures
-- Immutable closure snapshot for a finished event (US-13/US-14): totals are
-- captured once, at close time, so downstream reporting never recomputes
-- from mutable event_services/event_expenses/event_collaborators rows.
-- 1:1 with events via a primary key on event_id — no surrogate id, and
-- deliberately no created_at/updated_at/update trigger (design.md: the
-- snapshot is immutable by design, so nothing should ever update it).

create table public.event_closures (
  event_id uuid primary key references public.events (id) on delete restrict,
  services_total numeric(12, 2) not null,
  expenses_total numeric(12, 2) not null,
  payments_total numeric(12, 2) not null,
  deposit_amount numeric(12, 2) not null,
  remaining_balance numeric(12, 2) not null,
  -- Net financial result of the event: what services earned minus what
  -- was spent on expenses and collaborator payments.
  net_result numeric(12, 2) generated always as (
    services_total - expenses_total - payments_total
  ) stored,
  closed_by uuid not null references public.profiles (id) on delete restrict,
  closed_at timestamptz not null default now(),

  constraint event_closures_totals_ck check (
    services_total >= 0
    and expenses_total >= 0
    and payments_total >= 0
    and deposit_amount >= 0
  ),
  -- Amount still owed once the deposit is applied against services billed.
  constraint event_closures_remaining_balance_ck check (
    remaining_balance = services_total - deposit_amount
  )
);

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.event_closures enable row level security;
revoke all on public.event_closures from anon, authenticated;
