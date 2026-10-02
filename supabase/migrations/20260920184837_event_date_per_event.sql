-- Migration: event_date_per_event
-- Moves the event date from per-service (event_services.service_date) to
-- per-event (events.event_date). This is a deliberate design change that
-- supersedes design.md D8 ("no event_date column") and PRD rule 2 ("two
-- livestreams on different dates within the same event"): every service of
-- an event now shares the event's single date, while start_time/end_time
-- stay per service.
--
-- Order matters. Postgres will not drop event_services.service_date while
-- the views event_schedule and monthly_income_expense (and the hourly/unit
-- CHECKs) still reference it, so this migration:
--   1. adds events.event_date, backfills it, and makes it NOT NULL;
--   2. re-points the two dependent views at events.event_date;
--   3. replaces the two CHECKs that mention service_date;
--   4. drops the service_date index and the column itself.
-- The whole file runs in one transaction (Supabase CLI applies a migration
-- as a single batch, together with its schema_migrations bookkeeping row),
-- so a failure at any step leaves the previous schema untouched.
--
-- event_totals does not reference service_date and is intentionally left
-- alone. No function or trigger references service_date either (verified
-- against pg_depend / pg_proc / pg_trigger before writing this migration).

-- 1. events.event_date ------------------------------------------------------

alter table public.events add column event_date date;

-- Backfill: the earliest legacy service_date of the event; events with no
-- dated service (unit-only, or no services at all) fall back to the day
-- they were created. set_events_updated_at is disabled only for this UPDATE
-- so that a data backfill does not rewrite every event's updated_at.
alter table public.events disable trigger set_events_updated_at;

update public.events e
set event_date = coalesce(
  (select min(es.service_date) from public.event_services es where es.event_id = e.id),
  e.created_at::date
);

alter table public.events enable trigger set_events_updated_at;

alter table public.events alter column event_date set not null;

create index events_event_date_idx on public.events (event_date);

comment on column public.events.event_date is
  'The single calendar date of the event. Every service of the event shares it; start_time/end_time stay per service on event_services. Replaces the former per-service event_services.service_date (PRD rule 2, two livestreams on different dates within one event, no longer holds). No default: callers must choose the date explicitly.';

-- 2. Dependent views --------------------------------------------------------
-- create or replace (not drop + create) keeps each view's existing grants
-- and its security_invoker option; the column names/types/order are
-- unchanged, which is what create or replace requires.

-- event_schedule: still (event_id, starts_at, ends_at, staff_count), but the
-- date now comes from the event. starts_at/ends_at are event_date plus the
-- earliest hourly start_time / latest hourly end_time, or event_date 00:00
-- when the event has no timed service (unit-only or no services), so every
-- event now has a non-null window. Unit-billed services carry no times and
-- are ignored by min/max, exactly as before.
create or replace view public.event_schedule
with (security_invoker = true) as
select
  e.id as event_id,
  e.event_date + coalesce(sched.first_start, time '00:00') as starts_at,
  e.event_date + coalesce(sched.last_end, time '00:00') as ends_at,
  coalesce(staff.staff_count, 0) as staff_count
from public.events e
left join lateral (
  select
    min(es.start_time) as first_start,
    max(es.end_time) as last_end
  from public.event_services es
  where es.event_id = e.id
) sched on true
left join lateral (
  select count(*) as staff_count
  from public.event_staff st
  where st.event_id = e.id
) staff on true;

-- monthly_income_expense: income now keys off events.event_date (every
-- service inherits its event's month); expenses still key off
-- event_expenses.incurred_on. Because every service now has a month, unit-
-- billed services are no longer excluded (they were only excluded before
-- for having no service_date); income therefore equals event_totals'
-- services_total. Expenses with no incurred_on are still excluded.
create or replace view public.monthly_income_expense
with (security_invoker = true) as
select
  extract(year from combined.txn_date)::int as year,
  extract(month from combined.txn_date)::int as month,
  combined.event_id,
  sum(combined.income) as income,
  sum(combined.expenses) as expenses
from (
  select
    es.event_id,
    e.event_date as txn_date,
    es.subtotal as income,
    0::numeric(12, 2) as expenses
  from public.event_services es
  join public.events e on e.id = es.event_id

  union all

  select
    ee.event_id,
    ee.incurred_on as txn_date,
    0::numeric(12, 2) as income,
    ee.amount as expenses
  from public.event_expenses ee
  where ee.incurred_on is not null
) combined
group by 1, 2, combined.event_id;

-- 3. event_services CHECKs ---------------------------------------------------
-- Same rules as before minus every mention of service_date. Dropped and
-- re-added (validated against existing rows) before the column goes away.
-- The livestream CHECK does not mention service_date and is unchanged.

alter table public.event_services drop constraint event_services_hourly_ck;
alter table public.event_services drop constraint event_services_unit_ck;

-- Hourly rule: start_time/end_time/price_per_hour required, end_time
-- strictly after start_time (rule 4), price_per_hour positive (rule 5), and
-- unit fields must stay null. The date is the event's, not the service's.
alter table public.event_services add constraint event_services_hourly_ck check (
  service_type not in ('transmision_en_vivo', 'fotografias', 'entrevistas', 'anuncios')
  or (
    start_time is not null and end_time is not null
    and end_time > start_time
    and price_per_hour is not null and price_per_hour > 0
    and price_per_unit is null and quantity is null
  )
);

-- Unit rule: price_per_unit/quantity required and positive (rule 5), and
-- hourly fields must stay null.
alter table public.event_services add constraint event_services_unit_ck check (
  service_type not in ('fotos_impresas', 'fotos_enmarcadas', 'copia_evento')
  or (
    price_per_unit is not null and price_per_unit > 0
    and quantity is not null and quantity > 0
    and price_per_hour is null
    and start_time is null and end_time is null
  )
);

-- 4. Drop service_date -------------------------------------------------------

drop index public.event_services_service_date_idx;

alter table public.event_services drop column service_date;
