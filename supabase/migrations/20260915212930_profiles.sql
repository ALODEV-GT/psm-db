-- Migration: profiles
-- 1:1 extension of auth.users. handle_new_user() is the only writer of the
-- initial row: auth.users has non-Express write paths (GoTrue, Studio, the
-- seed script), so the profiles row must be created by a DB trigger, not an
-- Express service (see design.md D3).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'usuario',
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_profiles_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;

-- handle_new_user(): SECURITY DEFINER so the insert succeeds regardless of
-- the caller's RLS-restricted role, since it runs on every auth.users
-- insert (GoTrue signup, Studio, or the seed script), not only Express.
-- role is hardcoded to 'usuario' and NEVER read from raw_user_meta_data,
-- so a caller cannot self-promote to admin/tecnico via signup metadata.
-- Role changes remain an Express service operation (design.md D3).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email, 'Unnamed user'),
    'usuario'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
