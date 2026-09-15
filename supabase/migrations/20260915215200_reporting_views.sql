-- Migration: reporting_views
-- Three security_invoker views (design.md D7): event/period totals stay
-- plain queries over event_services/event_expenses/event_collaborators
-- instead of denormalized columns, so there is no drift to keep in sync.
-- WITH (security_invoker = true) makes every view evaluate under the
-- querying user's own RLS instead of the view owner's, keeping the D5
-- safety net honest for callers who query the view directly. Views cannot
-- carry row level security of their own — `alter ... enable row level
-- security` is only valid on tables — so security_invoker is the whole
-- security posture here, and each view inherits it from its underlying
-- tables' existing RLS (enabled, zero policies, revoked from anon/authenticated).

-- event_schedule: per-event start/end derived from event_services
-- (no denormalized event_date column — design.md D8) plus assigned staff
-- count. Serves US-01 (same-date warning), US-03 (ordering), US-04 (month
-- filter). Unit-billed services (no service_date) do not contribute a
-- schedule point; min/max ignore the nulls.
create view public.event_schedule
with (security_invoker = true) as
select
  e.id as event_id,
  sched.starts_at,
  sched.ends_at,
  coalesce(staff.staff_count, 0) as staff_count
from public.events e
left join lateral (
  select
    min(es.service_date + es.start_time) as starts_at,
    max(es.service_date + es.end_time) as ends_at
  from public.event_services es
  where es.event_id = e.id
) sched on true
left join lateral (
  select count(*) as staff_count
  from public.event_staff st
  where st.event_id = e.id
) staff on true;

-- event_totals: live per-event rollups (rule 7) mirroring event_closures'
-- remaining_balance formula, but computed from current rows rather than a
-- frozen snapshot.
create view public.event_totals
with (security_invoker = true) as
select
  e.id as event_id,
  coalesce(svc.services_total, 0) as services_total,
  coalesce(exp.expenses_total, 0) as expenses_total,
  coalesce(collab.payments_total, 0) as payments_total,
  coalesce(svc.services_total, 0) - e.deposit_amount as remaining_balance
from public.events e
left join lateral (
  select sum(es.subtotal) as services_total
  from public.event_services es
  where es.event_id = e.id
) svc on true
left join lateral (
  select sum(ee.amount) as expenses_total
  from public.event_expenses ee
  where ee.event_id = e.id
) exp on true
left join lateral (
  select sum(ec.payment_amount) as payments_total
  from public.event_collaborators ec
  where ec.event_id = e.id
) collab on true;

-- monthly_income_expense: per-event, per-calendar-month income (billed
-- services) vs. expenses, for US-14. Income keys off event_services'
-- service_date; expenses key off event_expenses' incurred_on. Rows with
-- neither date (e.g. unit-billed services with no service_date, or
-- expenses with no incurred_on) are excluded — they have no month to
-- report into.
create view public.monthly_income_expense
with (security_invoker = true) as
select
  extract(year from combined.txn_date)::int as year,
  extract(month from combined.txn_date)::int as month,
  combined.event_id,
  sum(combined.income) as income,
  sum(combined.expenses) as expenses
from (
  select
    es.event_id,
    es.service_date as txn_date,
    es.subtotal as income,
    0::numeric(12, 2) as expenses
  from public.event_services es
  where es.service_date is not null

  union all

  select
    ee.event_id,
    ee.incurred_on as txn_date,
    0::numeric(12, 2) as income,
    ee.amount as expenses
  from public.event_expenses ee
  where ee.incurred_on is not null
) combined
group by 1, 2, combined.event_id;
