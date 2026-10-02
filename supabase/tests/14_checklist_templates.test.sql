-- pgTAP test: migration 20261001200000_checklist_templates
-- Asserts checklist_templates exists as an admin-configurable catalog
-- (mirrors 13_expense_types.test.sql's shape coverage), tied to the
-- existing public.service_type enum, with a (service_type, lower(item))
-- unique constraint (same text within the same service_type is rejected,
-- but the same text under a different service_type is allowed), and RLS
-- default-deny.

begin;

select plan(12);

select has_table('public', 'checklist_templates', 'checklist_templates table exists');

select has_column('public', 'checklist_templates', 'service_type', 'checklist_templates has service_type column');
select col_not_null('public', 'checklist_templates', 'service_type', 'checklist_templates.service_type is NOT NULL');
select col_type_is('public', 'checklist_templates', 'service_type', 'service_type', 'checklist_templates.service_type is the shared service_type enum');

select has_column('public', 'checklist_templates', 'item', 'checklist_templates has item column');
select col_not_null('public', 'checklist_templates', 'item', 'checklist_templates.item is NOT NULL');

select has_column('public', 'checklist_templates', 'is_active', 'checklist_templates has is_active column');
select col_not_null('public', 'checklist_templates', 'is_active', 'checklist_templates.is_active is NOT NULL');
select col_default_is('public', 'checklist_templates', 'is_active', 'true', 'checklist_templates.is_active defaults to true');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.checklist_templates'::regclass),
  'RLS is enabled on checklist_templates'
);

-- (service_type, lower(item)) unique constraint

select throws_ok(
  $$ insert into public.checklist_templates (service_type, item)
     values ('fotografias', 'Revisar memoria'), ('fotografias', 'revisar memoria') $$,
  '23505',
  null,
  'checklist_templates rejects a case-insensitive duplicate item within the same service_type'
);

select lives_ok(
  $$ insert into public.checklist_templates (service_type, item)
     values ('fotografias', 'Mismo texto'), ('entrevistas', 'Mismo texto') $$,
  'checklist_templates allows the same item text under different service_type values'
);

select * from finish();

rollback;
