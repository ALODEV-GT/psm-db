-- pgTAP test: migration 03_clients
-- Asserts the clients table shape, name/email CHECKs, the created_by FK to
-- profiles (ON DELETE SET NULL), the case-insensitive search index on
-- lower(name), and RLS default-deny.

begin;

select plan(21);

-- Table + columns

select has_table('public', 'clients', 'clients table exists');

select has_column('public', 'clients', 'name', 'clients has name column');
select col_not_null('public', 'clients', 'name', 'clients.name is NOT NULL');

select has_column('public', 'clients', 'department', 'clients has department column');
select has_column('public', 'clients', 'municipality', 'clients has municipality column');
select has_column('public', 'clients', 'address', 'clients has address column');
select has_column('public', 'clients', 'phone', 'clients has phone column');
select has_column('public', 'clients', 'email', 'clients has email column');

select has_column('public', 'clients', 'created_by', 'clients has created_by column');
select col_type_is('public', 'clients', 'created_by', 'uuid', 'clients.created_by is uuid');
select fk_ok('public', 'clients', 'created_by', 'public', 'profiles', 'id', 'clients.created_by FKs to profiles.id');

select has_column('public', 'clients', 'created_at', 'clients has created_at column');
select has_column('public', 'clients', 'updated_at', 'clients has updated_at column');

-- RLS: enabled with zero policies (default-deny safety net, D5)

select ok(
  (select relrowsecurity from pg_class where oid = 'public.clients'::regclass),
  'RLS is enabled on clients'
);

-- name CHECK: btrim(name) <> ''

select throws_ok(
  $$ insert into public.clients (name) values ('   ') $$,
  '23514',
  null,
  'clients rejects a blank (whitespace-only) name'
);

-- email CHECK: null is allowed, otherwise must match a basic email pattern

select throws_ok(
  $$ insert into public.clients (name, email) values ('Acme', 'not-an-email') $$,
  '23514',
  null,
  'clients rejects an email missing @ and domain'
);

select throws_ok(
  $$ insert into public.clients (name, email) values ('Acme', 'foo@bar') $$,
  '23514',
  null,
  'clients rejects an email missing a dotted domain'
);

select lives_ok(
  $$ insert into public.clients (name, department, municipality, address, phone, email)
     values ('Acme Corp', 'Guatemala', 'Mixco', 'Calle 1', '555-1234', 'contact@acme.test') $$,
  'clients accepts a full row with a valid email'
);

select is(
  (select count(*) from public.clients where email = 'contact@acme.test'),
  1::bigint,
  'the valid client row was actually inserted'
);

-- created_by FK behavior: ON DELETE SET NULL, not CASCADE/RESTRICT

insert into auth.users (id, email, raw_user_meta_data)
values (
  '22222222-2222-2222-2222-222222222222',
  'client-owner@example.com',
  jsonb_build_object('full_name', 'Client Owner')
);

insert into public.clients (name, created_by)
values ('Owned Client', '22222222-2222-2222-2222-222222222222');

delete from auth.users where id = '22222222-2222-2222-2222-222222222222';

select is(
  (select created_by from public.clients where name = 'Owned Client'),
  null::uuid,
  'deleting the owning profile sets clients.created_by to null instead of blocking or cascading'
);

-- search index on lower(name) (US-06)

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'clients'
      and indexdef ilike '%lower(name)%'
  ),
  'clients has a case-insensitive search index on lower(name)'
);

select * from finish();

rollback;
