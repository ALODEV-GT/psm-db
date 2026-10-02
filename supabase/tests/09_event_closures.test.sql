-- pgTAP test: migration 09_event_closures
-- Asserts event_closures is a 1:1 snapshot keyed on event_id (no surrogate
-- id), remaining_balance CHECK, STORED generated net_result, and RLS
-- default-deny.

begin;

select plan(20);

-- Fixtures: client, event_type, two events (one for the happy path, one
-- shared by the two rejected-insert cases below), one profile as closer.

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');

insert into public.events (id, client_id, event_type_id, location, event_date)
values ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A', '2026-03-10');

insert into public.events (id, client_id, event_type_id, location, event_date)
values ('77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon B', '2026-03-11');

insert into auth.users (id, email, raw_user_meta_data)
values (
  '88888888-8888-8888-8888-888888888888',
  'closer-fixture@example.com',
  jsonb_build_object('full_name', 'Closer Fixture')
);

-- ==========================================================================
-- Shape
-- ==========================================================================

select has_table('public', 'event_closures', 'event_closures table exists');

select columns_are(
  'public', 'event_closures',
  array['event_id', 'services_total', 'expenses_total', 'payments_total', 'deposit_amount', 'remaining_balance', 'net_result', 'closed_by', 'closed_at'],
  'event_closures has exactly the expected columns'
);

select col_is_pk('public', 'event_closures', 'event_id', 'event_closures.event_id is the primary key (1:1 with events, no surrogate id)');
select fk_ok('public', 'event_closures', 'event_id', 'public', 'events', 'id', 'event_closures.event_id FKs to events.id');
select fk_ok('public', 'event_closures', 'closed_by', 'public', 'profiles', 'id', 'event_closures.closed_by FKs to profiles.id');

select col_not_null('public', 'event_closures', 'services_total', 'event_closures.services_total is NOT NULL');
select col_not_null('public', 'event_closures', 'expenses_total', 'event_closures.expenses_total is NOT NULL');
select col_not_null('public', 'event_closures', 'payments_total', 'event_closures.payments_total is NOT NULL');
select col_not_null('public', 'event_closures', 'deposit_amount', 'event_closures.deposit_amount is NOT NULL');
select col_not_null('public', 'event_closures', 'remaining_balance', 'event_closures.remaining_balance is NOT NULL');
select col_not_null('public', 'event_closures', 'closed_by', 'event_closures.closed_by is NOT NULL');
select col_not_null('public', 'event_closures', 'closed_at', 'event_closures.closed_at is NOT NULL');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_closures'::regclass),
  'RLS is enabled on event_closures'
);

-- ==========================================================================
-- Behavior
-- ==========================================================================

select lives_ok(
  $$ insert into public.event_closures
       (event_id, services_total, expenses_total, payments_total, deposit_amount, remaining_balance, closed_by)
     values
       ('66666666-6666-6666-6666-666666666666', 1000, 200, 100, 300, 700, '88888888-8888-8888-8888-888888888888') $$,
  'event_closures accepts a valid closure snapshot'
);

select results_eq(
  $$ select net_result from public.event_closures where event_id = '66666666-6666-6666-6666-666666666666' $$,
  $$ values (700.00::numeric(12,2)) $$,
  'net_result is generated as services_total - expenses_total - payments_total'
);

select throws_ok(
  $$ insert into public.event_closures
       (event_id, services_total, expenses_total, payments_total, deposit_amount, remaining_balance, closed_by)
     values
       ('66666666-6666-6666-6666-666666666666', 500, 0, 0, 0, 500, '88888888-8888-8888-8888-888888888888') $$,
  '23505',
  null,
  'event_closures rejects a second row for the same event_id (1:1 enforcement)'
);

select throws_ok(
  $$ insert into public.event_closures
       (event_id, services_total, expenses_total, payments_total, deposit_amount, remaining_balance, closed_by)
     values
       ('77777777-7777-7777-7777-777777777777', -10, 0, 0, 0, -10, '88888888-8888-8888-8888-888888888888') $$,
  '23514',
  null,
  'event_closures rejects a negative services_total'
);

select throws_ok(
  $$ insert into public.event_closures
       (event_id, services_total, expenses_total, payments_total, deposit_amount, remaining_balance, closed_by)
     values
       ('77777777-7777-7777-7777-777777777777', 100, 0, 0, 20, 999, '88888888-8888-8888-8888-888888888888') $$,
  '23514',
  null,
  'event_closures rejects a remaining_balance that does not equal services_total - deposit_amount'
);

select throws_ok(
  $$ delete from public.events where id = '66666666-6666-6666-6666-666666666666' $$,
  '23503',
  null,
  'deleting an event with an existing closure is rejected (RESTRICT)'
);

select throws_ok(
  $$ delete from public.profiles where id = '88888888-8888-8888-8888-888888888888' $$,
  '23503',
  null,
  'deleting a profile referenced as closed_by is rejected (RESTRICT)'
);

select * from finish();

rollback;
