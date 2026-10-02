-- pgTAP test: migration 04_events
-- Asserts the events table shape (including the per-event event_date that
-- replaced the per-service service_date), the RESTRICT FKs to
-- clients/event_types, the status default, the transmission-window CHECK,
-- and RLS default-deny.

begin;

select plan(42);

-- Table + columns

select has_table('public', 'events', 'events table exists');

select has_column('public', 'events', 'client_id', 'events has client_id column');
select col_not_null('public', 'events', 'client_id', 'events.client_id is NOT NULL');
select col_type_is('public', 'events', 'client_id', 'uuid', 'events.client_id is uuid');
select fk_ok('public', 'events', 'client_id', 'public', 'clients', 'id', 'events.client_id FKs to clients.id');

select has_column('public', 'events', 'event_type_id', 'events has event_type_id column');
select col_not_null('public', 'events', 'event_type_id', 'events.event_type_id is NOT NULL');
select col_type_is('public', 'events', 'event_type_id', 'uuid', 'events.event_type_id is uuid');
select fk_ok('public', 'events', 'event_type_id', 'public', 'event_types', 'id', 'events.event_type_id FKs to event_types.id');

select has_column('public', 'events', 'location', 'events has location column');
select col_not_null('public', 'events', 'location', 'events.location is NOT NULL');

select has_column('public', 'events', 'event_date', 'events has event_date column');
select col_not_null('public', 'events', 'event_date', 'events.event_date is NOT NULL');
select col_type_is('public', 'events', 'event_date', 'date', 'events.event_date is date');
select col_hasnt_default('public', 'events', 'event_date', 'events.event_date has no default (callers must choose the date explicitly)');

select has_column('public', 'events', 'notes', 'events has notes column');

select has_column('public', 'events', 'deposit_amount', 'events has deposit_amount column');
select col_not_null('public', 'events', 'deposit_amount', 'events.deposit_amount is NOT NULL');
select col_default_is('public', 'events', 'deposit_amount', '0', 'events.deposit_amount defaults to 0');

select has_column('public', 'events', 'status', 'events has status column');
select col_type_is('public', 'events', 'status', 'event_status', 'events.status is event_status enum');
select col_not_null('public', 'events', 'status', 'events.status is NOT NULL');
select col_default_is('public', 'events', 'status', 'programado', 'events.status defaults to programado');

select has_column('public', 'events', 'title', 'events has title column');
select has_column('public', 'events', 'subtitle', 'events has subtitle column');
select has_column('public', 'events', 'crawl', 'events has crawl column');
select has_column('public', 'events', 'transmission_started_at', 'events has transmission_started_at column');
select has_column('public', 'events', 'transmission_ended_at', 'events has transmission_ended_at column');

select has_column('public', 'events', 'created_by', 'events has created_by column');
select col_type_is('public', 'events', 'created_by', 'uuid', 'events.created_by is uuid');
select fk_ok('public', 'events', 'created_by', 'public', 'profiles', 'id', 'events.created_by FKs to profiles.id');

-- Indexes

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'events' and indexdef ilike '%(event_date)%'
  ),
  'events has an index on event_date'
);

-- RLS: enabled with zero policies (default-deny safety net, D5)

select ok(
  (select relrowsecurity from pg_class where oid = 'public.events'::regclass),
  'RLS is enabled on events'
);

-- Fixtures for behavioral tests

insert into public.clients (id, name) values ('33333333-3333-3333-3333-333333333333', 'Fixture Client');
insert into public.event_types (id, name) values ('44444444-4444-4444-4444-444444444444', 'Boda Fixture');

-- event_date NOT NULL: every event carries exactly one date

select throws_ok(
  $$ insert into public.events (client_id, event_type_id, location)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Salon A') $$,
  '23502',
  null,
  'events rejects an insert without event_date (NOT NULL)'
);

-- deposit_amount CHECK

select throws_ok(
  $$ insert into public.events (client_id, event_type_id, location, event_date, deposit_amount)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Salon A', '2026-03-10', -50) $$,
  '23514',
  null,
  'events rejects a negative deposit_amount'
);

-- transmission window CHECK

select throws_ok(
  $$ insert into public.events (client_id, event_type_id, location, event_date, transmission_ended_at)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Salon A', '2026-03-10', now()) $$,
  '23514',
  null,
  'events rejects transmission_ended_at set without transmission_started_at'
);

select throws_ok(
  $$ insert into public.events (client_id, event_type_id, location, event_date, transmission_started_at, transmission_ended_at)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Salon A', '2026-03-10', now(), now()) $$,
  '23514',
  null,
  'events rejects transmission_ended_at not strictly after transmission_started_at'
);

select lives_ok(
  $$ insert into public.events (client_id, event_type_id, location, event_date, transmission_started_at, transmission_ended_at)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Salon A', '2026-03-10', now(), now() + interval '1 hour') $$,
  'events accepts transmission_ended_at strictly after transmission_started_at'
);

select is(
  (select count(*) from public.events where location = 'Salon A'),
  1::bigint,
  'the valid event row was actually inserted'
);

select is(
  (select event_date from public.events where location = 'Salon A'),
  '2026-03-10'::date,
  'the inserted event row stores the supplied event_date'
);

-- RESTRICT FKs: neither client_id nor event_type_id parent can be deleted while referenced

select throws_ok(
  $$ delete from public.clients where id = '33333333-3333-3333-3333-333333333333' $$,
  '23503',
  null,
  'deleting a client referenced by an event is rejected (RESTRICT)'
);

select throws_ok(
  $$ delete from public.event_types where id = '44444444-4444-4444-4444-444444444444' $$,
  '23503',
  null,
  'deleting an event_type referenced by an event is rejected (RESTRICT)'
);

select * from finish();

rollback;
