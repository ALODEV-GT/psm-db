-- Migration: device_tokens
-- FCM registration tokens, one row per device install. A profile can have
-- several devices; a token belongs to exactly one profile at a time.

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_tokens_token_uq unique (token),
  constraint device_tokens_platform_ck check (platform in ('android'))
);

create index device_tokens_profile_id_idx on public.device_tokens (profile_id);

create trigger set_device_tokens_updated_at
  before update on public.device_tokens
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;
