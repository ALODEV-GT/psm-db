-- Migration: expense_types
-- expense_types: admin-configurable lookup table for event_expenses'
-- category, mirroring event_types/platforms exactly (migration
-- 20260915213051_lookup_tables.sql) — plain table, not an enum, so an
-- admin can add new expense types without a schema migration. Uniqueness
-- is case-insensitive on name.
--
-- event_expenses gains a nullable expense_type_id FK: existing rows have
-- no value and are not backfilled (no product data to backfill from); only
-- new application-layer writes are required to set it going forward,
-- enforced at the API layer, not the DB (ux-overhaul-batch-4 orchestrator
-- decision). concept becomes optional (a supplementary free-text note)
-- now that expense_type_id is the primary categorization, so its NOT NULL
-- and non-blank CHECK are relaxed to allow null while still rejecting a
-- present-but-blank value.

create table public.expense_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index expense_types_name_lower_uq on public.expense_types (lower(name));

create trigger set_expense_types_updated_at
  before update on public.expense_types
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.expense_types enable row level security;
revoke all on public.expense_types from anon, authenticated;

alter table public.event_expenses
  add column expense_type_id uuid references public.expense_types (id) on delete restrict;

-- concept was `not null check (btrim(concept) <> '')`; relax to nullable
-- while still rejecting a present-but-blank string.
alter table public.event_expenses
  drop constraint event_expenses_concept_ck;

alter table public.event_expenses
  alter column concept drop not null;

alter table public.event_expenses
  add constraint event_expenses_concept_ck check (concept is null or btrim(concept) <> '');
