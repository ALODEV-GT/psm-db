-- Migration: livestream_details
-- event_service_platforms and livestream_phone_numbers are children of
-- event_services that only make sense for transmision_en_vivo rows.
--
-- D10: each child table carries a redundant service_type column, defaulted
-- to 'transmision_en_vivo' so no writer path ever has to supply it, pinned
-- by a CHECK to that single value, and gated by a composite FK against
-- event_services' certifying unique(id, service_type) key (migration 05).
-- This makes it structurally impossible to attach a child to a
-- non-livestream service_type, both on insert and on a later UPDATE of the
-- parent's service_type away from transmision_en_vivo (the FK's default
-- NO ACTION blocks that too, since a matching child row would be
-- orphaned). See design.md D10 for the rejected alternatives (service
-- layer only; child-side trigger).

create table public.event_service_platforms (
  event_service_id uuid not null,
  platform_id uuid not null references public.platforms (id) on delete restrict,
  service_type public.service_type not null default 'transmision_en_vivo',
  created_at timestamptz not null default now(),

  primary key (event_service_id, platform_id),

  constraint event_service_platforms_livestream_only_ck check (service_type = 'transmision_en_vivo'),
  constraint event_service_platforms_service_fk foreign key (event_service_id, service_type)
    references public.event_services (id, service_type) on delete cascade
);

alter table public.event_service_platforms enable row level security;
revoke all on public.event_service_platforms from anon, authenticated;

create table public.livestream_phone_numbers (
  id uuid primary key default gen_random_uuid(),
  event_service_id uuid not null,
  phone_number text not null,
  service_type public.service_type not null default 'transmision_en_vivo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint livestream_phone_numbers_phone_number_ck check (phone_number ~ '^[0-9+()\-\s]{8,20}$'),
  constraint livestream_phone_numbers_event_service_id_phone_number_uq unique (event_service_id, phone_number),

  constraint livestream_phone_numbers_livestream_only_ck check (service_type = 'transmision_en_vivo'),
  constraint livestream_phone_numbers_service_fk foreign key (event_service_id, service_type)
    references public.event_services (id, service_type) on delete cascade
);

create trigger set_livestream_phone_numbers_updated_at
  before update on public.livestream_phone_numbers
  for each row
  execute function public.set_updated_at();

alter table public.livestream_phone_numbers enable row level security;
revoke all on public.livestream_phone_numbers from anon, authenticated;
