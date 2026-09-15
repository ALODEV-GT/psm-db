-- Migration: clients
-- The party a company (event) is booked for. name is required; every other
-- descriptive field is optional. created_by tracks the profile that
-- registered the client but must not block/cascade profile deletion — a
-- client record outlives the staff member who created it (SET NULL).

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  department text,
  municipality text,
  address text,
  phone text,
  email text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_name_not_blank_ck check (btrim(name) <> ''),
  constraint clients_email_format_ck check (
    email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  )
);

-- Case-insensitive search index (US-06) — a plain (non-unique) expression
-- index; clients.name has no uniqueness requirement in the design.
create index clients_name_lower_idx on public.clients (lower(name));

create trigger set_clients_updated_at
  before update on public.clients
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.clients enable row level security;
revoke all on public.clients from anon, authenticated;
