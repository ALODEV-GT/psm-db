-- pgTAP test: migration 07_event_checklist_timeline
-- Asserts event_checklist (unique(event_id, item), is_completed <->
-- completed_at CHECK) and timeline_notes (body/elapsed-time CHECKs) shape,
-- event_id CASCADE, and RLS default-deny.

begin;

select plan(35);

-- Fixtures: client, event_type, event

insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Fixture Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Boda Fixture');
insert into public.events (id, client_id, event_type_id, location)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Salon A');

-- ==========================================================================
-- event_checklist
-- ==========================================================================

select has_table('public', 'event_checklist', 'event_checklist table exists');

select has_column('public', 'event_checklist', 'event_id', 'event_checklist has event_id column');
select col_not_null('public', 'event_checklist', 'event_id', 'event_checklist.event_id is NOT NULL');
select fk_ok('public', 'event_checklist', 'event_id', 'public', 'events', 'id', 'event_checklist.event_id FKs to events.id');

select has_column('public', 'event_checklist', 'item', 'event_checklist has item column');
select col_not_null('public', 'event_checklist', 'item', 'event_checklist.item is NOT NULL');
select col_type_is('public', 'event_checklist', 'item', 'checklist_item', 'event_checklist.item is checklist_item enum');

select has_column('public', 'event_checklist', 'is_completed', 'event_checklist has is_completed column');
select col_not_null('public', 'event_checklist', 'is_completed', 'event_checklist.is_completed is NOT NULL');
select col_default_is('public', 'event_checklist', 'is_completed', 'false', 'event_checklist.is_completed defaults to false');

select has_column('public', 'event_checklist', 'completed_at', 'event_checklist has completed_at column');

select has_column('public', 'event_checklist', 'completed_by', 'event_checklist has completed_by column');
select fk_ok('public', 'event_checklist', 'completed_by', 'public', 'profiles', 'id', 'event_checklist.completed_by FKs to profiles.id');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.event_checklist'::regclass),
  'RLS is enabled on event_checklist'
);

-- unique(event_id, item)

select lives_ok(
  $$ insert into public.event_checklist (event_id, item)
     values ('33333333-3333-3333-3333-333333333333', 'audio') $$,
  'event_checklist accepts the first (event_id, item) pair'
);

select throws_ok(
  $$ insert into public.event_checklist (event_id, item)
     values ('33333333-3333-3333-3333-333333333333', 'audio') $$,
  '23505',
  null,
  'event_checklist rejects a duplicate (event_id, item) pair'
);

-- is_completed <-> completed_at CHECK

select throws_ok(
  $$ insert into public.event_checklist (event_id, item, is_completed, completed_at)
     values ('33333333-3333-3333-3333-333333333333', 'video', true, null) $$,
  '23514',
  null,
  'event_checklist rejects is_completed=true with completed_at null'
);

select throws_ok(
  $$ insert into public.event_checklist (event_id, item, is_completed, completed_at)
     values ('33333333-3333-3333-3333-333333333333', 'video', false, now()) $$,
  '23514',
  null,
  'event_checklist rejects is_completed=false with completed_at set'
);

select lives_ok(
  $$ insert into public.event_checklist (event_id, item, is_completed, completed_at)
     values ('33333333-3333-3333-3333-333333333333', 'video', true, now()) $$,
  'event_checklist accepts is_completed=true with completed_at set'
);

-- ==========================================================================
-- timeline_notes
-- ==========================================================================

select has_table('public', 'timeline_notes', 'timeline_notes table exists');

select has_column('public', 'timeline_notes', 'event_id', 'timeline_notes has event_id column');
select col_not_null('public', 'timeline_notes', 'event_id', 'timeline_notes.event_id is NOT NULL');
select fk_ok('public', 'timeline_notes', 'event_id', 'public', 'events', 'id', 'timeline_notes.event_id FKs to events.id');

select has_column('public', 'timeline_notes', 'body', 'timeline_notes has body column');
select col_not_null('public', 'timeline_notes', 'body', 'timeline_notes.body is NOT NULL');

select has_column('public', 'timeline_notes', 'elapsed_seconds', 'timeline_notes has elapsed_seconds column');
select col_not_null('public', 'timeline_notes', 'elapsed_seconds', 'timeline_notes.elapsed_seconds is NOT NULL');

select has_column('public', 'timeline_notes', 'created_by', 'timeline_notes has created_by column');
select fk_ok('public', 'timeline_notes', 'created_by', 'public', 'profiles', 'id', 'timeline_notes.created_by FKs to profiles.id');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.timeline_notes'::regclass),
  'RLS is enabled on timeline_notes'
);

-- body CHECK: not blank

select throws_ok(
  $$ insert into public.timeline_notes (event_id, body, elapsed_seconds)
     values ('33333333-3333-3333-3333-333333333333', '   ', 0) $$,
  '23514',
  null,
  'timeline_notes rejects a blank body'
);

-- elapsed_seconds CHECK: >= 0

select throws_ok(
  $$ insert into public.timeline_notes (event_id, body, elapsed_seconds)
     values ('33333333-3333-3333-3333-333333333333', 'Audio check complete', -1) $$,
  '23514',
  null,
  'timeline_notes rejects a negative elapsed_seconds'
);

select lives_ok(
  $$ insert into public.timeline_notes (event_id, body, elapsed_seconds)
     values ('33333333-3333-3333-3333-333333333333', 'Audio check complete', 0) $$,
  'timeline_notes accepts a valid note with elapsed_seconds=0'
);

-- event_id CASCADE: deleting the event removes both checklist and
-- timeline_notes rows

delete from public.events where id = '33333333-3333-3333-3333-333333333333';

select is(
  (select count(*) from public.event_checklist where event_id = '33333333-3333-3333-3333-333333333333'),
  0::bigint,
  'event_checklist rows are cascade-deleted when their event is deleted'
);

select is(
  (select count(*) from public.timeline_notes where event_id = '33333333-3333-3333-3333-333333333333'),
  0::bigint,
  'timeline_notes rows are cascade-deleted when their event is deleted'
);

select * from finish();

rollback;
