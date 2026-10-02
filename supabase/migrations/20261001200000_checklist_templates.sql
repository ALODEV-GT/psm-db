-- Migration: checklist_templates
-- checklist_templates: admin-configurable catalog of pre-flight checklist
-- items, each tied to exactly one service_type (reusing the existing
-- public.service_type enum, not a new type). Mirrors expense_types' shape
-- (migration 20260925185424_expense_types.sql) plus the extra required
-- service_type column. An event's real event_checklist rows are generated
-- at creation time from the templates matching the event's selected
-- services (Express service-layer concern, not this migration's).
--
-- event_checklist is altered as a clean BREAKING change (no backward
-- compatibility needed — the user confirmed the dev DB will be wiped and
-- reseeded after this ships):
--   - item: public.checklist_item (4 fixed enum values) -> text not null,
--     since checklist items become admin-free-form text.
--   - template_id: new nullable FK to checklist_templates, traceability
--     only (on delete set null; not required for any functional read path).
-- The now-unused public.checklist_item enum type is dropped after the
-- column conversion (confirmed via grep: only this table's own column and
-- its own pgTAP tests referenced it; both are updated in this change).

create table public.checklist_templates (
  id uuid primary key default gen_random_uuid(),
  service_type public.service_type not null,
  item text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index checklist_templates_service_type_item_lower_uq
  on public.checklist_templates (service_type, lower(item));

create trigger set_checklist_templates_updated_at
  before update on public.checklist_templates
  for each row
  execute function public.set_updated_at();

-- RLS: enable + zero policies + explicit revoke = default-deny safety net.
-- This is NOT the authorization boundary; the Express service layer (using
-- the service_role key, which bypasses RLS) owns authorization (design.md D5).
alter table public.checklist_templates enable row level security;
revoke all on public.checklist_templates from anon, authenticated;

-- event_checklist.item: enum -> text (clean breaking change, no data to
-- preserve beyond the literal string values, which `::text` keeps as-is).
alter table public.event_checklist
  alter column item type text using item::text;

alter table public.event_checklist
  add column template_id uuid references public.checklist_templates (id) on delete set null;

-- public.checklist_item is now unused by any column; safe to drop.
drop type public.checklist_item;
