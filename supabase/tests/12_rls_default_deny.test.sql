-- pgTAP test: RLS default-deny, whole schema
-- Proves the D5 security posture end-to-end for all 14 domain tables in one
-- pass: RLS enabled + zero policies + explicit `revoke all from anon,
-- authenticated` means the anon role can read zero rows from any table.
--
-- Each table's own migration already asserts `relrowsecurity` individually
-- (see 01-09 test files). This file is the missing whole-schema proof that
-- an anon-role query is actually rejected, not merely that the flag is set.
--
-- `set role anon` reproduces exactly what PostgREST does per-request when
-- the caller presents the anon key (it issues `set local role anon` before
-- running the query), so this is the same code path a `curl` against
-- `/rest/v1/<table>` with the anon apikey exercises. Because every table
-- also has `revoke all ... from anon` (not just RLS-with-a-deny-policy),
-- the denial surfaces as a permission error (`42501`), not an empty result
-- set — a stronger form of "anon gets zero rows" than a silently-filtered
-- 200 response would be.

begin;

select plan(14);

set role anon;
select throws_ok(
  $$ select 1 from public.profiles limit 1 $$,
  '42501', null,
  'anon cannot read any row from profiles'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.clients limit 1 $$,
  '42501', null,
  'anon cannot read any row from clients'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_types limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_types'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.platforms limit 1 $$,
  '42501', null,
  'anon cannot read any row from platforms'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.events limit 1 $$,
  '42501', null,
  'anon cannot read any row from events'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_services limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_services'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_service_platforms limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_service_platforms'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.livestream_phone_numbers limit 1 $$,
  '42501', null,
  'anon cannot read any row from livestream_phone_numbers'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_checklist limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_checklist'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.timeline_notes limit 1 $$,
  '42501', null,
  'anon cannot read any row from timeline_notes'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_staff limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_staff'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_collaborators limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_collaborators'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_expenses limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_expenses'
);
reset role;

set role anon;
select throws_ok(
  $$ select 1 from public.event_closures limit 1 $$,
  '42501', null,
  'anon cannot read any row from event_closures'
);
reset role;

select * from finish();

rollback;
