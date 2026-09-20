-- pgTAP test: migration 10_reporting_views
-- Asserts event_schedule, event_totals, and monthly_income_expense exist,
-- carry security_invoker=true (design.md D7), and return correctly
-- aggregated rows. Views have no RLS of their own — security_invoker makes
-- them respect the querying user's RLS on the underlying tables instead of
-- the view owner's, so there is nothing to enable here.
--
-- The event date is per event (events.event_date), not per service: every
-- event has a non-null event_schedule window (event_date + earliest hourly
-- start_time .. event_date + latest hourly end_time, falling back to
-- 00:00), and monthly_income_expense keys income on events.event_date.

begin;

select plan(22);

-- Fixtures: client, event_type, one staff profile.

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');

insert into auth.users (id, email, raw_user_meta_data)
values (
  '44444444-4444-4444-4444-444444444444',
  'schedule-staff-fixture@example.com',
  jsonb_build_object('full_name', 'Schedule Staff Fixture')
);

-- Event A: rich data — one hourly service, one unit service (no times, so
-- it must not contribute to starts_at/ends_at but does count as income in
-- the event's month), one expense, one collaborator payment, one staff
-- assignment.
insert into public.events (id, client_id, event_type_id, location, event_date, deposit_amount)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A', '2026-03-10', 100);

insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
values ('33333333-3333-3333-3333-333333333333', 'fotografias', '10:00', '12:00', 100);

insert into public.event_services (event_id, service_type, price_per_unit, quantity)
values ('33333333-3333-3333-3333-333333333333', 'fotos_impresas', 10, 3);

insert into public.event_expenses (event_id, concept, amount, incurred_on)
values ('33333333-3333-3333-3333-333333333333', 'Catering', 50, '2026-03-15');

insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
values ('33333333-3333-3333-3333-333333333333', null, 'Ayudante', 40);

insert into public.event_staff (event_id, profile_id)
values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444');

-- Event B: no services, expenses, collaborators, or staff — proves the
-- coalesce/null-safe rollup path and the event_date 00:00 schedule fallback.
insert into public.events (id, client_id, event_type_id, location, event_date)
values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon B', '2026-06-01');

-- Event C: two hourly services on the same (event-level) date — the
-- schedule window spans the earliest start to the latest end — plus an
-- expense incurred in a different month than the event, proving income
-- keys off event_date while expenses key off incurred_on.
insert into public.events (id, client_id, event_type_id, location, event_date)
values ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon C', '2026-04-05');

insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
values
  ('66666666-6666-6666-6666-666666666666', 'fotografias', '09:00', '11:00', 100),
  ('66666666-6666-6666-6666-666666666666', 'entrevistas', '14:00', '17:30', 100);

insert into public.event_expenses (event_id, concept, amount, incurred_on)
values ('66666666-6666-6666-6666-666666666666', 'Transporte', 25, '2026-05-02');

-- Event D: unit-billed services only (no start/end time anywhere) — the
-- schedule falls back to event_date at 00:00 and income lands in the
-- event's month.
insert into public.events (id, client_id, event_type_id, location, event_date)
values ('77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon D', '2026-05-20');

insert into public.event_services (event_id, service_type, price_per_unit, quantity)
values ('77777777-7777-7777-7777-777777777777', 'fotos_enmarcadas', 20, 2);

-- ==========================================================================
-- Shape
-- ==========================================================================

select has_view('public', 'event_schedule', 'event_schedule view exists');
select has_view('public', 'event_totals', 'event_totals view exists');
select has_view('public', 'monthly_income_expense', 'monthly_income_expense view exists');

select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.event_schedule'::regclass),
  'event_schedule has security_invoker=true'
);
select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.event_totals'::regclass),
  'event_totals has security_invoker=true'
);
select ok(
  (select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.monthly_income_expense'::regclass),
  'monthly_income_expense has security_invoker=true'
);

-- ==========================================================================
-- event_schedule
-- ==========================================================================

select columns_are(
  'public', 'event_schedule',
  array['event_id', 'starts_at', 'ends_at', 'staff_count'],
  'event_schedule keeps its output contract: exactly (event_id, starts_at, ends_at, staff_count)'
);
select col_type_is('public', 'event_schedule', 'event_id', 'uuid', 'event_schedule.event_id is uuid');
select col_type_is('public', 'event_schedule', 'starts_at', 'timestamp without time zone', 'event_schedule.starts_at is timestamp');
select col_type_is('public', 'event_schedule', 'ends_at', 'timestamp without time zone', 'event_schedule.ends_at is timestamp');
select col_type_is('public', 'event_schedule', 'staff_count', 'bigint', 'event_schedule.staff_count is bigint');

select results_eq(
  $$ select event_id, starts_at, ends_at, staff_count
     from public.event_schedule
     where event_id = '33333333-3333-3333-3333-333333333333' $$,
  $$ values (
       '33333333-3333-3333-3333-333333333333'::uuid,
       '2026-03-10 10:00:00'::timestamp,
       '2026-03-10 12:00:00'::timestamp,
       1::bigint
     ) $$,
  'event_schedule = event_date + the hourly service times (unit service ignored) and counts staff for event A'
);

select results_eq(
  $$ select event_id, starts_at, ends_at, staff_count
     from public.event_schedule
     where event_id = '66666666-6666-6666-6666-666666666666' $$,
  $$ values (
       '66666666-6666-6666-6666-666666666666'::uuid,
       '2026-04-05 09:00:00'::timestamp,
       '2026-04-05 17:30:00'::timestamp,
       0::bigint
     ) $$,
  'event_schedule spans event_date + earliest start_time to event_date + latest end_time across several services'
);

select results_eq(
  $$ select event_id, starts_at, ends_at, staff_count
     from public.event_schedule
     where event_id = '77777777-7777-7777-7777-777777777777' $$,
  $$ values (
       '77777777-7777-7777-7777-777777777777'::uuid,
       '2026-05-20 00:00:00'::timestamp,
       '2026-05-20 00:00:00'::timestamp,
       0::bigint
     ) $$,
  'event_schedule falls back to event_date 00:00 for an event with only unit-billed services'
);

select results_eq(
  $$ select event_id, starts_at, ends_at, staff_count
     from public.event_schedule
     where event_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values (
       '55555555-5555-5555-5555-555555555555'::uuid,
       '2026-06-01 00:00:00'::timestamp,
       '2026-06-01 00:00:00'::timestamp,
       0::bigint
     ) $$,
  'event_schedule falls back to event_date 00:00 and zero staff_count for an event with no services or staff'
);

select is_empty(
  $$ select 1 from public.event_schedule
     where event_id in (
       '33333333-3333-3333-3333-333333333333',
       '55555555-5555-5555-5555-555555555555',
       '66666666-6666-6666-6666-666666666666',
       '77777777-7777-7777-7777-777777777777'
     )
     and (starts_at is null or ends_at is null) $$,
  'every event has a non-null starts_at/ends_at in event_schedule'
);

-- ==========================================================================
-- event_totals
-- ==========================================================================

select results_eq(
  $$ select event_id, services_total, expenses_total, payments_total, remaining_balance
     from public.event_totals
     where event_id = '33333333-3333-3333-3333-333333333333' $$,
  $$ values (
       '33333333-3333-3333-3333-333333333333'::uuid,
       230.00::numeric(12,2),
       50.00::numeric(12,2),
       40.00::numeric(12,2),
       130.00::numeric(12,2)
     ) $$,
  'event_totals sums services/expenses/payments and computes remaining_balance for event A'
);

select results_eq(
  $$ select event_id, services_total, expenses_total, payments_total, remaining_balance
     from public.event_totals
     where event_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values (
       '55555555-5555-5555-5555-555555555555'::uuid,
       0::numeric(12,2),
       0::numeric(12,2),
       0::numeric(12,2),
       0::numeric(12,2)
     ) $$,
  'event_totals returns all zeros for an event with no services, expenses, or payments'
);

-- ==========================================================================
-- monthly_income_expense
-- ==========================================================================

select results_eq(
  $$ select year, month, event_id, income, expenses
     from public.monthly_income_expense
     where event_id = '33333333-3333-3333-3333-333333333333' $$,
  $$ values (
       2026,
       3,
       '33333333-3333-3333-3333-333333333333'::uuid,
       230.00::numeric(12,2),
       50.00::numeric(12,2)
     ) $$,
  'monthly_income_expense groups event A''s income (hourly + unit services, keyed on event_date) and expense into the same March 2026 row'
);

select results_eq(
  $$ select year, month, event_id, income, expenses
     from public.monthly_income_expense
     where event_id = '66666666-6666-6666-6666-666666666666'
     order by month $$,
  $$ values
       (2026, 4, '66666666-6666-6666-6666-666666666666'::uuid, 550.00::numeric(12,2), 0.00::numeric(12,2)),
       (2026, 5, '66666666-6666-6666-6666-666666666666'::uuid, 0.00::numeric(12,2), 25.00::numeric(12,2)) $$,
  'monthly_income_expense keys event C''s income on event_date (April) and its expense on incurred_on (May)'
);

select results_eq(
  $$ select year, month, event_id, income, expenses
     from public.monthly_income_expense
     where event_id = '77777777-7777-7777-7777-777777777777' $$,
  $$ values (
       2026,
       5,
       '77777777-7777-7777-7777-777777777777'::uuid,
       40.00::numeric(12,2),
       0.00::numeric(12,2)
     ) $$,
  'monthly_income_expense reports a unit-only event''s income in the month of its event_date'
);

select is_empty(
  $$ select 1 from public.monthly_income_expense
     where event_id = '55555555-5555-5555-5555-555555555555' $$,
  'monthly_income_expense has no row for an event with no services or expenses'
);

select * from finish();

rollback;
