-- Migration: lookup_tables
-- event_types and platforms: admin-configurable lookup tables (plain
-- tables, not enums, so an admin can add new types/platforms without a
-- schema migration). Uniqueness is case-insensitive on name.

create table public.event_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- table-level UNIQUE only accepts a column list, not an expression, so
-- case-insensitive uniqueness needs a unique expression index instead.
create unique index event_types_name_lower_uq on public.event_types (lower(name));

create trigger set_event_types_updated_at
  before update on public.event_types
  for each row
  execute function public.set_updated_at();

alter table public.event_types enable row level security;
revoke all on public.event_types from anon, authenticated;

create table public.platforms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index platforms_name_lower_uq on public.platforms (lower(name));

create trigger set_platforms_updated_at
  before update on public.platforms
  for each row
  execute function public.set_updated_at();

alter table public.platforms enable row level security;
revoke all on public.platforms from anon, authenticated;
