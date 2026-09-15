-- Migration: event_services
-- Polymorphic line-item table discriminated by service_type: hourly-billed
-- types (transmision_en_vivo, fotografias, entrevistas, anuncios) carry a
-- schedule + price_per_hour; unit-billed types (fotos_impresas,
-- fotos_enmarcadas, copia_evento) carry price_per_unit + quantity.
-- transmision_en_vivo additionally requires a livestream visibility value.
--
-- unique(id, service_type) is a certifying key: it exists only so
-- migration 06's event_service_platforms/livestream_phone_numbers can
-- carry a redundant, CHECK-pinned service_type column and FK against
-- (id, service_type), gating those child inserts to livestream parents
-- declaratively (design.md D10). It has no meaning on its own here.

create table public.event_services (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  service_type public.service_type not null,
  service_date date,
  start_time time,
  end_time time,
  price_per_hour numeric(12, 2),
  price_per_unit numeric(12, 2),
  quantity integer,
  visibility public.livestream_visibility,
  stream_title text,
  stream_description text,
  -- extract(epoch from (time - time)) is IMMUTABLE, so this is legal in a
  -- STORED generated column.
  subtotal numeric(12, 2) generated always as (
    case
      when price_per_hour is not null
        then round((extract(epoch from (end_time - start_time)) / 3600.0)::numeric * price_per_hour, 2)
      else round(quantity * price_per_unit, 2)
    end
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Hourly rule: service_date/start_time/end_time/price_per_hour required,
  -- end_time strictly after start_time (rule 4), price_per_hour positive
  -- (rule 5), and unit fields must stay null.
  constraint event_services_hourly_ck check (
    service_type not in ('transmision_en_vivo', 'fotografias', 'entrevistas', 'anuncios')
    or (
      service_date is not null and start_time is not null and end_time is not null
      and end_time > start_time
      and price_per_hour is not null and price_per_hour > 0
      and price_per_unit is null and quantity is null
    )
  ),

  -- Unit rule: price_per_unit/quantity required and positive (rule 5), and
  -- hourly fields must stay null.
  constraint event_services_unit_ck check (
    service_type not in ('fotos_impresas', 'fotos_enmarcadas', 'copia_evento')
    or (
      price_per_unit is not null and price_per_unit > 0
      and quantity is not null and quantity > 0
      and price_per_hour is null and service_date is null
      and start_time is null and end_time is null
    )
  ),

  -- Livestream visibility rule: transmision_en_vivo requires visibility;
  -- every other type must leave visibility/stream_title/stream_description null.
  constraint event_services_livestream_ck check (
    (service_type = 'transmision_en_vivo' and visibility is not null)
    or (
      service_type <> 'transmision_en_vivo'
      and visibility is null and stream_title is null and stream_description is null
    )
  ),

  -- Certifying key for migration 06's D10 child FKs.
  constraint event_services_id_type_uq unique (id, service_type)
);

create index event_services_event_id_idx on public.event_services (event_id);
create index event_services_service_date_idx on public.event_services (service_date);

create trigger set_event_services_updated_at
  before update on public.event_services
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.event_services enable row level security;
revoke all on public.event_services from anon, authenticated;
