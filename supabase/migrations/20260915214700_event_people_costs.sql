-- Migration: event_people_costs
-- event_staff assigns crew to an event (composite PK, no surrogate id).
-- event_collaborators pays either a registered profile or an ad-hoc payee
-- (profile_id nullable, display_name required — resolves the exploration's
-- open question: US-12 supports both registered users and one-off payees).
-- event_expenses records event-scoped costs.

create table public.event_staff (
  event_id uuid not null references public.events (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  assigned_at timestamptz not null default now(),

  primary key (event_id, profile_id)
);

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.event_staff enable row level security;
revoke all on public.event_staff from anon, authenticated;

create table public.event_collaborators (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete set null,
  display_name text not null,
  payment_amount numeric(12, 2) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint event_collaborators_payment_amount_ck check (payment_amount >= 0)
);

create index event_collaborators_event_id_idx on public.event_collaborators (event_id);

create trigger set_event_collaborators_updated_at
  before update on public.event_collaborators
  for each row
  execute function public.set_updated_at();

alter table public.event_collaborators enable row level security;
revoke all on public.event_collaborators from anon, authenticated;

create table public.event_expenses (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete set null,
  concept text not null,
  amount numeric(12, 2) not null,
  incurred_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint event_expenses_concept_ck check (btrim(concept) <> ''),
  constraint event_expenses_amount_ck check (amount > 0)
);

create index event_expenses_event_id_idx on public.event_expenses (event_id);

create trigger set_event_expenses_updated_at
  before update on public.event_expenses
  for each row
  execute function public.set_updated_at();

alter table public.event_expenses enable row level security;
revoke all on public.event_expenses from anon, authenticated;
