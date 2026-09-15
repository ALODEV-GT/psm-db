-- pgTAP test: migration 02_lookup_tables
-- Asserts event_types and platforms exist as admin-configurable lookup
-- tables with case-insensitive unique names and RLS default-deny.

begin;

select plan(16);

-- event_types

select has_table('public', 'event_types', 'event_types table exists');
select has_column('public', 'event_types', 'name', 'event_types has name column');
select col_not_null('public', 'event_types', 'name', 'event_types.name is NOT NULL');
select has_column('public', 'event_types', 'is_active', 'event_types has is_active column');
select col_not_null('public', 'event_types', 'is_active', 'event_types.is_active is NOT NULL');
select col_default_is('public', 'event_types', 'is_active', 'true', 'event_types.is_active defaults to true');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_types'::regclass),
  'RLS is enabled on event_types'
);

select throws_ok(
  $$ insert into public.event_types (name) values ('Boda'), ('boda') $$,
  '23505',
  null,
  'event_types rejects a case-insensitive duplicate name'
);

-- platforms

select has_table('public', 'platforms', 'platforms table exists');
select has_column('public', 'platforms', 'name', 'platforms has name column');
select col_not_null('public', 'platforms', 'name', 'platforms.name is NOT NULL');
select has_column('public', 'platforms', 'is_active', 'platforms has is_active column');
select col_not_null('public', 'platforms', 'is_active', 'platforms.is_active is NOT NULL');
select col_default_is('public', 'platforms', 'is_active', 'true', 'platforms.is_active defaults to true');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.platforms'::regclass),
  'RLS is enabled on platforms'
);

select throws_ok(
  $$ insert into public.platforms (name) values ('YouTube'), ('youtube') $$,
  '23505',
  null,
  'platforms rejects a case-insensitive duplicate name'
);

select * from finish();

rollback;
