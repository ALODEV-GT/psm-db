-- pgTAP test: migration 01_profiles
-- Asserts the profiles table shape, RLS default-deny, and that
-- handle_new_user() creates a profiles row on auth.users insert with
-- role hardcoded to 'usuario' regardless of any user_metadata role claim.

begin;

select plan(24);

-- Table + columns

select has_table('public', 'profiles', 'profiles table exists');

select has_column('public', 'profiles', 'id', 'profiles has id column');
select col_type_is('public', 'profiles', 'id', 'uuid', 'profiles.id is uuid');
select col_is_pk('public', 'profiles', 'id', 'profiles.id is the primary key');
select fk_ok('public', 'profiles', 'id', 'auth', 'users', 'id', 'profiles.id FKs to auth.users.id');

select has_column('public', 'profiles', 'full_name', 'profiles has full_name column');
select col_not_null('public', 'profiles', 'full_name', 'profiles.full_name is NOT NULL');

select has_column('public', 'profiles', 'role', 'profiles has role column');
select col_type_is('public', 'profiles', 'role', 'user_role', 'profiles.role is user_role enum');
select col_not_null('public', 'profiles', 'role', 'profiles.role is NOT NULL');
select col_default_is('public', 'profiles', 'role', 'usuario', 'profiles.role defaults to usuario');

select has_column('public', 'profiles', 'phone', 'profiles has phone column');

select has_column('public', 'profiles', 'is_active', 'profiles has is_active column');
select col_not_null('public', 'profiles', 'is_active', 'profiles.is_active is NOT NULL');
select col_default_is('public', 'profiles', 'is_active', 'true', 'profiles.is_active defaults to true');

select has_column('public', 'profiles', 'created_at', 'profiles has created_at column');
select has_column('public', 'profiles', 'updated_at', 'profiles has updated_at column');

-- RLS: enabled with zero policies (default-deny safety net, D5)

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS is enabled on profiles'
);

-- handle_new_user() trigger: exists, SECURITY DEFINER, fires on auth.users insert

select has_function('public', 'handle_new_user', 'handle_new_user() function exists');
select ok(
  (select prosecdef from pg_proc where oid = 'public.handle_new_user()'::regprocedure),
  'handle_new_user() is SECURITY DEFINER'
);
select has_trigger('auth', 'users', 'on_auth_user_created', 'on_auth_user_created trigger exists on auth.users');

insert into auth.users (id, email, raw_user_meta_data)
values (
  '11111111-1111-1111-1111-111111111111',
  'trigger-test@example.com',
  jsonb_build_object('full_name', 'Trigger Test', 'role', 'admin')
);

select is(
  (select count(*) from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'handle_new_user() created exactly one profiles row on auth.users insert'
);

select results_eq(
  $$ select role::text from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('usuario') $$,
  'handle_new_user() hardcodes role to usuario, ignoring user_metadata role=admin'
);

select results_eq(
  $$ select full_name from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('Trigger Test') $$,
  'handle_new_user() populates full_name from user_metadata'
);

select * from finish();

rollback;
