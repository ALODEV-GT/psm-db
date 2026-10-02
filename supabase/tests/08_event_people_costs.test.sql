-- pgTAP test: migration 08_event_people_costs
-- Asserts event_staff (composite PK), event_collaborators (nullable
-- profile_id + required display_name), event_expenses (amount CHECK), and
-- RLS default-deny on all three.

begin;

select plan(53);

-- Fixtures: client, event_type, event, one profile (via auth.users insert
-- so handle_new_user's trigger creates the profiles row)

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');
insert into public.events (id, client_id, event_type_id, location, event_date)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A', '2026-03-10');

insert into auth.users (id, email, raw_user_meta_data)
values (
  '44444444-4444-4444-4444-444444444444',
  'staff-fixture@example.com',
  jsonb_build_object('full_name', 'Staff Fixture')
);

-- ==========================================================================
-- event_staff
-- ==========================================================================

select has_table('public', 'event_staff', 'event_staff table exists');

select has_column('public', 'event_staff', 'event_id', 'event_staff has event_id column');
select col_not_null('public', 'event_staff', 'event_id', 'event_staff.event_id is NOT NULL');
select fk_ok('public', 'event_staff', 'event_id', 'public', 'events', 'id', 'event_staff.event_id FKs to events.id');

select has_column('public', 'event_staff', 'profile_id', 'event_staff has profile_id column');
select col_not_null('public', 'event_staff', 'profile_id', 'event_staff.profile_id is NOT NULL');
select fk_ok('public', 'event_staff', 'profile_id', 'public', 'profiles', 'id', 'event_staff.profile_id FKs to profiles.id');

select has_column('public', 'event_staff', 'assigned_at', 'event_staff has assigned_at column');
select col_not_null('public', 'event_staff', 'assigned_at', 'event_staff.assigned_at is NOT NULL');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_staff'::regclass),
  'RLS is enabled on event_staff'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.event_staff'::regclass
      and contype = 'p'
      and conkey = (
        select array_agg(attnum order by attnum) from pg_attribute
        where attrelid = 'public.event_staff'::regclass
          and attname in ('event_id', 'profile_id')
      )
  ),
  'event_staff has a composite primary key (event_id, profile_id)'
);

select lives_ok(
  $$ insert into public.event_staff (event_id, profile_id)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444') $$,
  'event_staff accepts the first (event_id, profile_id) pair'
);

select throws_ok(
  $$ insert into public.event_staff (event_id, profile_id)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444') $$,
  '23505',
  null,
  'event_staff rejects a duplicate (event_id, profile_id) pair'
);

select throws_ok(
  $$ delete from public.profiles where id = '44444444-4444-4444-4444-444444444444' $$,
  '23503',
  null,
  'deleting a profile still assigned as event_staff is rejected (RESTRICT)'
);

-- ==========================================================================
-- event_collaborators
-- ==========================================================================

select has_table('public', 'event_collaborators', 'event_collaborators table exists');

select has_column('public', 'event_collaborators', 'event_id', 'event_collaborators has event_id column');
select col_not_null('public', 'event_collaborators', 'event_id', 'event_collaborators.event_id is NOT NULL');
select fk_ok('public', 'event_collaborators', 'event_id', 'public', 'events', 'id', 'event_collaborators.event_id FKs to events.id');

select has_column('public', 'event_collaborators', 'profile_id', 'event_collaborators has profile_id column');
select col_is_null('public', 'event_collaborators', 'profile_id', 'event_collaborators.profile_id is nullable (ad-hoc payees)');
select fk_ok('public', 'event_collaborators', 'profile_id', 'public', 'profiles', 'id', 'event_collaborators.profile_id FKs to profiles.id');

select has_column('public', 'event_collaborators', 'display_name', 'event_collaborators has display_name column');
select col_not_null('public', 'event_collaborators', 'display_name', 'event_collaborators.display_name is NOT NULL');

select has_column('public', 'event_collaborators', 'payment_amount', 'event_collaborators has payment_amount column');
select col_not_null('public', 'event_collaborators', 'payment_amount', 'event_collaborators.payment_amount is NOT NULL');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_collaborators'::regclass),
  'RLS is enabled on event_collaborators'
);

select lives_ok(
  $$ insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
     values ('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', 'Staff Fixture', 100) $$,
  'event_collaborators accepts a registered-user row with profile_id set'
);

select lives_ok(
  $$ insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
     values ('33333333-3333-3333-3333-333333333333', null, 'Ad-hoc Helper', 50) $$,
  'event_collaborators accepts an ad-hoc payee row with profile_id null'
);

select throws_ok(
  $$ insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
     values ('33333333-3333-3333-3333-333333333333', null, null, 50) $$,
  '23502',
  null,
  'event_collaborators rejects a null display_name'
);

select throws_ok(
  $$ insert into public.event_collaborators (event_id, profile_id, display_name, payment_amount)
     values ('33333333-3333-3333-3333-333333333333', null, 'Negative Helper', -10) $$,
  '23514',
  null,
  'event_collaborators rejects a negative payment_amount'
);

-- ==========================================================================
-- event_expenses
-- ==========================================================================

select has_table('public', 'event_expenses', 'event_expenses table exists');

select has_column('public', 'event_expenses', 'event_id', 'event_expenses has event_id column');
select col_not_null('public', 'event_expenses', 'event_id', 'event_expenses.event_id is NOT NULL');
select fk_ok('public', 'event_expenses', 'event_id', 'public', 'events', 'id', 'event_expenses.event_id FKs to events.id');

select has_column('public', 'event_expenses', 'profile_id', 'event_expenses has profile_id column');
select col_is_null('public', 'event_expenses', 'profile_id', 'event_expenses.profile_id is nullable');
select fk_ok('public', 'event_expenses', 'profile_id', 'public', 'profiles', 'id', 'event_expenses.profile_id FKs to profiles.id');

select has_column('public', 'event_expenses', 'concept', 'event_expenses has concept column');
select col_is_null('public', 'event_expenses', 'concept', 'event_expenses.concept is nullable (optional note, expense_type_id is now the primary categorization)');

select has_column('public', 'event_expenses', 'amount', 'event_expenses has amount column');
select col_not_null('public', 'event_expenses', 'amount', 'event_expenses.amount is NOT NULL');

select has_column('public', 'event_expenses', 'incurred_on', 'event_expenses has incurred_on column');

select has_column('public', 'event_expenses', 'expense_type_id', 'event_expenses has expense_type_id column');
select col_is_null('public', 'event_expenses', 'expense_type_id', 'event_expenses.expense_type_id is nullable (no backfill for existing rows)');
select fk_ok('public', 'event_expenses', 'expense_type_id', 'public', 'expense_types', 'id', 'event_expenses.expense_type_id FKs to expense_types.id');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_expenses'::regclass),
  'RLS is enabled on event_expenses'
);

select throws_ok(
  $$ insert into public.event_expenses (event_id, concept, amount)
     values ('33333333-3333-3333-3333-333333333333', '   ', 25) $$,
  '23514',
  null,
  'event_expenses rejects a present-but-blank concept'
);

select throws_ok(
  $$ insert into public.event_expenses (event_id, concept, amount)
     values ('33333333-3333-3333-3333-333333333333', 'Catering', 0) $$,
  '23514',
  null,
  'event_expenses rejects a zero amount'
);

select lives_ok(
  $$ insert into public.event_expenses (event_id, concept, amount)
     values ('33333333-3333-3333-3333-333333333333', 'Catering', 25.50) $$,
  'event_expenses accepts a valid positive amount'
);

select lives_ok(
  $$ insert into public.event_expenses (event_id, amount)
     values ('33333333-3333-3333-3333-333333333333', 15) $$,
  'event_expenses accepts a null concept (existing rows, no backfill)'
);

insert into public.expense_types (id, name) values ('55555555-5555-5555-5555-555555555555', 'Transporte Fixture');

select lives_ok(
  $$ insert into public.event_expenses (event_id, expense_type_id, amount)
     values ('33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555', 40) $$,
  'event_expenses accepts a valid expense_type_id'
);

select throws_ok(
  $$ insert into public.event_expenses (event_id, expense_type_id, amount)
     values ('33333333-3333-3333-3333-333333333333', '99999999-9999-9999-9999-999999999999', 40) $$,
  '23503',
  null,
  'event_expenses rejects a non-existent expense_type_id (RESTRICT FK)'
);

select throws_ok(
  $$ delete from public.expense_types where id = '55555555-5555-5555-5555-555555555555' $$,
  '23503',
  null,
  'deleting an expense_types row still referenced by event_expenses is rejected (RESTRICT)'
);

select * from finish();

rollback;
