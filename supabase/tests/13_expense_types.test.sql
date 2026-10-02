-- pgTAP test: migration 13_expense_types
-- Asserts expense_types exists as an admin-configurable lookup table with
-- case-insensitive unique names and RLS default-deny (mirrors
-- 02_lookup_tables.test.sql's event_types/platforms coverage), and that
-- event_expenses.expense_type_id is a nullable FK to it.

begin;

select plan(11);

select has_table('public', 'expense_types', 'expense_types table exists');
select has_column('public', 'expense_types', 'name', 'expense_types has name column');
select col_not_null('public', 'expense_types', 'name', 'expense_types.name is NOT NULL');
select has_column('public', 'expense_types', 'is_active', 'expense_types has is_active column');
select col_not_null('public', 'expense_types', 'is_active', 'expense_types.is_active is NOT NULL');
select col_default_is('public', 'expense_types', 'is_active', 'true', 'expense_types.is_active defaults to true');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.expense_types'::regclass),
  'RLS is enabled on expense_types'
);

select throws_ok(
  $$ insert into public.expense_types (name) values ('Internet'), ('internet') $$,
  '23505',
  null,
  'expense_types rejects a case-insensitive duplicate name'
);

select has_column('public', 'event_expenses', 'expense_type_id', 'event_expenses has expense_type_id column');
select col_is_null('public', 'event_expenses', 'expense_type_id', 'event_expenses.expense_type_id is nullable');
select fk_ok('public', 'event_expenses', 'expense_type_id', 'public', 'expense_types', 'id', 'event_expenses.expense_type_id FKs to expense_types.id');

select * from finish();

rollback;
