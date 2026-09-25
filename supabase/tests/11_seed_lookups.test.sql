-- pgTAP test: supabase/seed.sql
-- Asserts seed.sql loads the expected event_types/platforms/expense_types
-- rows on `supabase db reset`, and that its ON CONFLICT clauses make a
-- re-run idempotent (no duplicate-key error, no row-count change).

begin;

select plan(5);

select is(
  (
    select count(*)::int
    from public.event_types
    where lower(name) in ('boda', 'cumpleaños', 'graduación', 'quinceañera', 'corporativo')
  ),
  5,
  'seed.sql loads the five expected event_types rows'
);

select is(
  (
    select count(*)::int
    from public.platforms
    where lower(name) in ('facebook', 'youtube', 'tiktok')
  ),
  3,
  'seed.sql loads the three expected platforms rows'
);

select is(
  (
    select count(*)::int
    from public.expense_types
    where lower(name) in ('internet', 'transporte', 'alimentación', 'otros')
  ),
  4,
  'seed.sql loads the four expected expense_types rows'
);

-- Idempotency: re-running the same insert pattern must not error and must
-- not change the row count (ON CONFLICT (lower(name)) DO NOTHING).
select lives_ok(
  $$ insert into public.event_types (name) values ('Boda') on conflict (lower(name)) do nothing $$,
  'event_types seed insert pattern is idempotent (re-run does not error)'
);

select is(
  (select count(*)::int from public.event_types where lower(name) = 'boda'),
  1,
  'event_types re-run insert did not create a duplicate row'
);

select * from finish();

rollback;
