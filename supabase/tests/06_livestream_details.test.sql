-- pgTAP test: migration 06_livestream_details
-- Asserts event_service_platforms and livestream_phone_numbers shape, the
-- D10 pinned service_type column (default + CHECK), the composite FK
-- gating both insert and parent-UPDATE to livestream-only event_services
-- rows, and RLS default-deny.

begin;

select plan(39);

-- Fixtures: client, event_type, event, one livestream parent (A) and one
-- non-livestream parent (B) event_services row, plus a platform.

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');
insert into public.events (id, client_id, event_type_id, location)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A');

insert into public.event_services (id, event_id, service_type, service_date, start_time, end_time, price_per_hour, visibility, stream_title, stream_description)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'transmision_en_vivo',
  current_date, '09:00', '12:00', 200, 'publico', 'Wedding stream', 'Live wedding ceremony'
);

insert into public.event_services (id, event_id, service_type, service_date, start_time, end_time, price_per_hour)
values (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', 'fotografias',
  current_date, '13:00', '15:00', 100
);

insert into public.platforms (id, name) values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Facebook Fixture');

-- ==========================================================================
-- event_service_platforms
-- ==========================================================================

select has_table('public', 'event_service_platforms', 'event_service_platforms table exists');

select has_column('public', 'event_service_platforms', 'event_service_id', 'event_service_platforms has event_service_id column');
select col_not_null('public', 'event_service_platforms', 'event_service_id', 'event_service_platforms.event_service_id is NOT NULL');
select col_type_is('public', 'event_service_platforms', 'event_service_id', 'uuid', 'event_service_platforms.event_service_id is uuid');

select has_column('public', 'event_service_platforms', 'platform_id', 'event_service_platforms has platform_id column');
select col_not_null('public', 'event_service_platforms', 'platform_id', 'event_service_platforms.platform_id is NOT NULL');
select fk_ok('public', 'event_service_platforms', 'platform_id', 'public', 'platforms', 'id', 'event_service_platforms.platform_id FKs to platforms.id');

select has_column('public', 'event_service_platforms', 'service_type', 'event_service_platforms has service_type column');
select col_not_null('public', 'event_service_platforms', 'service_type', 'event_service_platforms.service_type is NOT NULL');
select col_type_is('public', 'event_service_platforms', 'service_type', 'service_type', 'event_service_platforms.service_type is service_type enum');
select col_default_is('public', 'event_service_platforms', 'service_type', 'transmision_en_vivo', 'event_service_platforms.service_type defaults to transmision_en_vivo');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_service_platforms'::regclass),
  'RLS is enabled on event_service_platforms'
);

-- Composite PK (event_service_id, platform_id), no surrogate id

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.event_service_platforms'::regclass
      and contype = 'p'
      and conkey = (
        select array_agg(attnum order by attnum) from pg_attribute
        where attrelid = 'public.event_service_platforms'::regclass
          and attname in ('event_service_id', 'platform_id')
      )
  ),
  'event_service_platforms has a composite primary key (event_service_id, platform_id)'
);

-- D10 composite FK gate: (event_service_id, service_type) -> event_services(id, service_type)

select fk_ok(
  'public', 'event_service_platforms', ARRAY['event_service_id', 'service_type'],
  'public', 'event_services', ARRAY['id', 'service_type'],
  'event_service_platforms has the D10 composite FK to event_services(id, service_type)'
);

-- D10 behavioral: insert rejected against a non-livestream parent

select throws_ok(
  $$ insert into public.event_service_platforms (event_service_id, platform_id)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
  '23503',
  null,
  'event_service_platforms insert rejected against a non-livestream event_services parent'
);

-- D10 behavioral: CHECK rejects an explicit non-default service_type even
-- when the referenced parent is a livestream row

select throws_ok(
  $$ insert into public.event_service_platforms (event_service_id, platform_id, service_type)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'fotografias') $$,
  '23514',
  null,
  'event_service_platforms rejects an explicit service_type other than transmision_en_vivo'
);

-- D10 behavioral: insert accepted against a livestream parent, relying on
-- the service_type column default (no writer supplies it)

select lives_ok(
  $$ insert into public.event_service_platforms (event_service_id, platform_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
  'event_service_platforms insert accepted against a livestream event_services parent'
);

-- platform_id RESTRICT: cannot delete a platform still referenced by a child

select throws_ok(
  $$ delete from public.platforms where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  '23503',
  null,
  'deleting a platform still referenced by event_service_platforms is rejected (RESTRICT)'
);

-- D10 behavioral: parent UPDATE away from transmision_en_vivo is rejected
-- while an event_service_platforms child still exists (NO ACTION default)

select throws_ok(
  $$ update public.event_services
       set service_type = 'fotografias', visibility = null, stream_title = null, stream_description = null
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '23503',
  null,
  'parent event_services.service_type UPDATE away from transmision_en_vivo is rejected while an event_service_platforms child exists'
);

-- ==========================================================================
-- livestream_phone_numbers
-- ==========================================================================

select has_table('public', 'livestream_phone_numbers', 'livestream_phone_numbers table exists');

select has_column('public', 'livestream_phone_numbers', 'event_service_id', 'livestream_phone_numbers has event_service_id column');
select col_not_null('public', 'livestream_phone_numbers', 'event_service_id', 'livestream_phone_numbers.event_service_id is NOT NULL');
select col_type_is('public', 'livestream_phone_numbers', 'event_service_id', 'uuid', 'livestream_phone_numbers.event_service_id is uuid');

select has_column('public', 'livestream_phone_numbers', 'phone_number', 'livestream_phone_numbers has phone_number column');
select col_not_null('public', 'livestream_phone_numbers', 'phone_number', 'livestream_phone_numbers.phone_number is NOT NULL');

select has_column('public', 'livestream_phone_numbers', 'service_type', 'livestream_phone_numbers has service_type column');
select col_not_null('public', 'livestream_phone_numbers', 'service_type', 'livestream_phone_numbers.service_type is NOT NULL');
select col_type_is('public', 'livestream_phone_numbers', 'service_type', 'service_type', 'livestream_phone_numbers.service_type is service_type enum');
select col_default_is('public', 'livestream_phone_numbers', 'service_type', 'transmision_en_vivo', 'livestream_phone_numbers.service_type defaults to transmision_en_vivo');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.livestream_phone_numbers'::regclass),
  'RLS is enabled on livestream_phone_numbers'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.livestream_phone_numbers'::regclass
      and contype = 'u'
      and conkey = (
        select array_agg(attnum order by attnum) from pg_attribute
        where attrelid = 'public.livestream_phone_numbers'::regclass
          and attname in ('event_service_id', 'phone_number')
      )
  ),
  'livestream_phone_numbers has a unique(event_service_id, phone_number) constraint'
);

select fk_ok(
  'public', 'livestream_phone_numbers', ARRAY['event_service_id', 'service_type'],
  'public', 'event_services', ARRAY['id', 'service_type'],
  'livestream_phone_numbers has the D10 composite FK to event_services(id, service_type)'
);

-- phone_number CHECK: ^[0-9+()\-\s]{8,20}$

select throws_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'not-a-phone') $$,
  '23514',
  null,
  'livestream_phone_numbers rejects a phone_number that does not match the allowed format'
);

select throws_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '123') $$,
  '23514',
  null,
  'livestream_phone_numbers rejects a phone_number shorter than 8 characters'
);

-- D10 behavioral: insert rejected against a non-livestream parent

select throws_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '+502 5555-1234') $$,
  '23503',
  null,
  'livestream_phone_numbers insert rejected against a non-livestream event_services parent'
);

-- D10 behavioral: CHECK rejects an explicit non-default service_type

select throws_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number, service_type)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '+502 5555-1234', 'fotografias') $$,
  '23514',
  null,
  'livestream_phone_numbers rejects an explicit service_type other than transmision_en_vivo'
);

-- D10 behavioral: insert accepted against a livestream parent, relying on
-- the service_type column default

select lives_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '+502 5555-1234') $$,
  'livestream_phone_numbers insert accepted against a livestream event_services parent'
);

-- unique(event_service_id, phone_number): duplicate rejected

select throws_ok(
  $$ insert into public.livestream_phone_numbers (event_service_id, phone_number)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '+502 5555-1234') $$,
  '23505',
  null,
  'livestream_phone_numbers rejects a duplicate (event_service_id, phone_number) pair'
);

-- D10 behavioral: parent UPDATE away from transmision_en_vivo is rejected
-- while a livestream_phone_numbers child still exists too (NO ACTION default)

select throws_ok(
  $$ update public.event_services
       set service_type = 'fotografias', visibility = null, stream_title = null, stream_description = null
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '23503',
  null,
  'parent event_services.service_type UPDATE away from transmision_en_vivo is rejected while a livestream_phone_numbers child exists'
);

select * from finish();

rollback;
