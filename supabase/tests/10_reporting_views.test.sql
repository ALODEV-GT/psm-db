-- pgTAP test: migration 10_reporting_views
-- Asserts event_schedule, event_totals, and monthly_income_expense exist,
-- carry security_invoker=true (design.md D7), and return correctly
-- aggregated rows. Views have no RLS of their own — security_invoker makes
-- them respect the querying user's RLS on the underlying tables instead of
-- the view owner's, so there is nothing to enable here.

begin;

select plan(12);

-- Fixtures: client, event_type, one staff profile.

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');

insert into auth.users (id, email, raw_user_meta_data)
values (
  '44444444-4444-4444-4444-444444444444',
  'schedule-staff-fixture@example.com',
  jsonb_build_object('full_name', 'Schedule Staff Fixture')
);

-- Event A: rich data — one hourly service, one unit service (no
-- service_date, so it must be excluded from starts_at/ends_at/monthly
-- income), one expense, one collaborator payment, one staff assignment.
insert into public.events (id, client_id, event_type_id, location, deposit_amount)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A', 100);

insert into public.event_services (event_id, service_type, service_date, start_time, end_time, price_per_hour)
values ('33333333-3333-3333-3333-333333333333', 'fotografias', '2026-03-10', '10:00', '12:00', 100);

insert into public.event_services (event_id, service_type, price_per_unit, quantity)
values ('33333333-3333-3333-3333-333333333333', 'fotos_impresas', 10, 3);

insert into public.event_expenses (event_id, concept, amount, incurred_on)
values ('33333333-3333-3333-3333-333333333333', 'Catering', 50, '2026-03-15');

insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
values ('33333333-3333-3333-3333-333333333333', null, 'Ayudante', 40);

insert into public.event_staff (event_id, profile_id)
values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444');

-- Event B: no services, expenses, collaborators, or staff — proves the
-- coalesce/null-safe rollup path.
insert into public.events (id, client_id, event_type_id, location)
values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon B');

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
  'event_schedule derives starts_at/ends_at from the hourly service only and counts staff for event A'
);

select results_eq(
  $$ select event_id, starts_at, ends_at, staff_count
     from public.event_schedule
     where event_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values (
       '55555555-5555-5555-5555-555555555555'::uuid,
       null::timestamp,
       null::timestamp,
       0::bigint
     ) $$,
  'event_schedule returns null starts_at/ends_at and zero staff_count for an event with no services or staff'
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
       200.00::numeric(12,2),
       50.00::numeric(12,2)
     ) $$,
  'monthly_income_expense groups event A''s hourly-service income and expense into the same March 2026 row (unit service excluded, no service_date)'
);

select is_empty(
  $$ select 1 from public.monthly_income_expense
     where event_id = '55555555-5555-5555-5555-555555555555' $$,
  'monthly_income_expense has no row for an event with no dated services or expenses'
);

select * from finish();

rollback;
