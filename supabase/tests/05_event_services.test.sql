-- pgTAP test: migration 05_event_services
-- Asserts the event_services table shape, the hourly/unit/livestream CHECK
-- constraints, the certifying unique(id, service_type) key consumed by
-- D10's child FKs (migration 06), the event_id CASCADE, and RLS
-- default-deny. subtotal math (STORED generated column) is proven
-- separately by results_eq cases (task 2.7 REFACTOR).
--
-- The service date no longer lives here: the event date moved to
-- events.event_date (migration event_date_per_event), so event_services
-- carries only per-service start_time/end_time. This file also proves that
-- service_date, its index, and every reference to it in the CHECKs are gone.

begin;

select plan(45);

-- Table + columns

select has_table('public', 'event_services', 'event_services table exists');

select has_column('public', 'event_services', 'event_id', 'event_services has event_id column');
select col_not_null('public', 'event_services', 'event_id', 'event_services.event_id is NOT NULL');
select col_type_is('public', 'event_services', 'event_id', 'uuid', 'event_services.event_id is uuid');
select fk_ok('public', 'event_services', 'event_id', 'public', 'events', 'id', 'event_services.event_id FKs to events.id');

select has_column('public', 'event_services', 'service_type', 'event_services has service_type column');
select col_not_null('public', 'event_services', 'service_type', 'event_services.service_type is NOT NULL');
select col_type_is('public', 'event_services', 'service_type', 'service_type', 'event_services.service_type is service_type enum');

select hasnt_column('public', 'event_services', 'service_date', 'event_services no longer has a service_date column (date moved to events.event_date)');
select has_column('public', 'event_services', 'start_time', 'event_services has start_time column');
select has_column('public', 'event_services', 'end_time', 'event_services has end_time column');
select has_column('public', 'event_services', 'price_per_hour', 'event_services has price_per_hour column');
select has_column('public', 'event_services', 'price_per_unit', 'event_services has price_per_unit column');
select has_column('public', 'event_services', 'quantity', 'event_services has quantity column');
select has_column('public', 'event_services', 'visibility', 'event_services has visibility column');
select has_column('public', 'event_services', 'stream_title', 'event_services has stream_title column');
select has_column('public', 'event_services', 'stream_description', 'event_services has stream_description column');
select has_column('public', 'event_services', 'subtotal', 'event_services has subtotal column');
select has_column('public', 'event_services', 'created_at', 'event_services has created_at column');
select has_column('public', 'event_services', 'updated_at', 'event_services has updated_at column');

-- RLS: enabled with zero policies (default-deny safety net, D5)

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_services'::regclass),
  'RLS is enabled on event_services'
);

-- Certifying composite unique key consumed by D10's child FKs (migration 06)

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.event_services'::regclass
      and contype = 'u'
      and conkey = (
        select array_agg(attnum order by attnum) from pg_attribute
        where attrelid = 'public.event_services'::regclass
          and attname in ('id', 'service_type')
      )
  ),
  'event_services has a certifying unique(id, service_type) constraint'
);

-- Indexes

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'event_services' and indexdef ilike '%(event_id)%'
  ),
  'event_services has an index on event_id'
);

select hasnt_index('public', 'event_services', 'event_services_service_date_idx', 'event_services_service_date_idx is dropped');

select ok(
  not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'event_services' and indexdef ilike '%service_date%'
  ),
  'no index on event_services references service_date'
);

-- CHECK constraints: none may mention the dropped service_date column

select ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.event_services'::regclass
      and pg_get_constraintdef(oid) ilike '%service_date%'
  ),
  'no event_services constraint references service_date'
);

-- Fixtures for behavioral tests

insert into public.clients (id, name) values ('55555555-5555-5555-5555-555555555555', 'Fixture Client');
insert into public.event_types (id, name) values ('66666666-6666-6666-6666-666666666666', 'Boda Fixture');
insert into public.events (id, client_id, event_type_id, location, event_date)
values ('77777777-7777-7777-7777-777777777777', '55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666', 'Salon A', '2026-03-10');

-- Hourly rule (rule 4 + rule 5): start_time/end_time/price_per_hour required
-- (no service date — it is the event's), end_time > start_time,
-- price_per_hour > 0, unit fields must be null.
-- Uses 'fotografias' (an hourly type outside the livestream-specific CHECK).

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', 100) $$,
  '23514',
  null,
  'hourly service_type rejected when start_time/end_time are missing'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, end_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '10:00', 100) $$,
  '23514',
  null,
  'hourly service_type rejected when only start_time is missing'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', 100) $$,
  '23514',
  null,
  'hourly service_type rejected when only end_time is missing'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '10:00', '09:00', 100) $$,
  '23514',
  null,
  'hourly service_type rejected when end_time is not after start_time (rule 4)'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '10:00', 0) $$,
  '23514',
  null,
  'hourly service_type rejected when price_per_hour is not positive (rule 5)'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour, quantity)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '10:00', 100, 2) $$,
  '23514',
  null,
  'hourly service_type rejected when a unit field (quantity) is also set'
);

select lives_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '11:00', 100) $$,
  'hourly service_type accepted with start_time/end_time/price_per_hour and no service_date'
);

-- Unit rule (rule 5): price_per_unit/quantity required and positive, hourly
-- fields must be null. Uses 'fotos_impresas' (a unit-billed type).

select throws_ok(
  $$ insert into public.event_services (event_id, service_type)
     values ('77777777-7777-7777-7777-777777777777', 'fotos_impresas') $$,
  '23514',
  null,
  'unit service_type rejected when price_per_unit/quantity are missing'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, price_per_unit, quantity)
     values ('77777777-7777-7777-7777-777777777777', 'fotos_impresas', 10, 0) $$,
  '23514',
  null,
  'unit service_type rejected when quantity is not positive'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, price_per_unit, quantity, start_time)
     values ('77777777-7777-7777-7777-777777777777', 'fotos_impresas', 10, 5, '09:00') $$,
  '23514',
  null,
  'unit service_type rejected when an hourly field (start_time) is also set'
);

select lives_ok(
  $$ insert into public.event_services (event_id, service_type, price_per_unit, quantity)
     values ('77777777-7777-7777-7777-777777777777', 'fotos_impresas', 10, 5) $$,
  'unit service_type accepted with a complete, valid set of unit fields'
);

-- Livestream visibility rule: transmision_en_vivo requires visibility;
-- every other type must leave visibility/stream_title/stream_description null.
-- transmision_en_vivo is also an hourly type, so valid rows need both.

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour)
     values ('77777777-7777-7777-7777-777777777777', 'transmision_en_vivo', '09:00', '10:00', 200) $$,
  '23514',
  null,
  'transmision_en_vivo rejected without a visibility value'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour, visibility)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '10:00', 100, 'publico') $$,
  '23514',
  null,
  'a non-livestream service_type rejected when visibility is set'
);

select throws_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour, stream_title)
     values ('77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '10:00', 100, 'Should not be here') $$,
  '23514',
  null,
  'a non-livestream service_type rejected when stream_title is set'
);

select lives_ok(
  $$ insert into public.event_services (event_id, service_type, start_time, end_time, price_per_hour, visibility, stream_title, stream_description)
     values ('77777777-7777-7777-7777-777777777777', 'transmision_en_vivo', '09:00', '12:00', 200, 'publico', 'Wedding stream', 'Live wedding ceremony') $$,
  'transmision_en_vivo accepted with visibility and optional stream fields set'
);

-- subtotal math (STORED generated column): hourly and unit paths use
-- different formulas, so both must be proven with real computed values.

insert into public.event_services (id, event_id, service_type, start_time, end_time, price_per_hour)
values ('88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777777', 'fotografias', '09:00', '11:30', 100);

select results_eq(
  $$ select subtotal from public.event_services where id = '88888888-8888-8888-8888-888888888888' $$,
  $$ values (250.00::numeric(12,2)) $$,
  'hourly subtotal = (end_time - start_time in hours) * price_per_hour: 2.5h * 100 = 250.00'
);

insert into public.event_services (id, event_id, service_type, price_per_unit, quantity)
values ('99999999-9999-9999-9999-999999999999', '77777777-7777-7777-7777-777777777777', 'fotos_impresas', 15.50, 4);

select results_eq(
  $$ select subtotal from public.event_services where id = '99999999-9999-9999-9999-999999999999' $$,
  $$ values (62.00::numeric(12,2)) $$,
  'unit subtotal = quantity * price_per_unit: 4 * 15.50 = 62.00'
);

-- event_id CASCADE: deleting the parent event removes its event_services rows

select is(
  (select count(*) from public.event_services where event_id = '77777777-7777-7777-7777-777777777777'),
  5::bigint,
  'all 5 fixture event_services rows (3 CHECK cases + 2 subtotal cases) exist before the parent event is deleted'
);

delete from public.events where id = '77777777-7777-7777-7777-777777777777';

select is(
  (select count(*) from public.event_services where event_id = '77777777-7777-7777-7777-777777777777'),
  0::bigint,
  'deleting the parent event cascades to remove its event_services rows'
);

select * from finish();

rollback;
