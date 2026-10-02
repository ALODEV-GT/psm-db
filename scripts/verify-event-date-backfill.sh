#!/usr/bin/env bash
# Backfill proof for migration 20260920184837_event_date_per_event.sql.
#
# After that migration event_services.service_date no longer exists, so a
# pgTAP test (which always runs against the fully migrated schema) cannot
# insert legacy-shaped rows. This script proves the backfill instead: it
# builds a throwaway database inside the local Supabase Postgres container,
# applies every migration BEFORE event_date_per_event, inserts legacy-shaped
# data, applies the new migration, and asserts the results. The scratch
# database is dropped on exit; the real dev database is never touched.
#
# Requires the local Supabase stack (`npm run db:start`). Run from the
# database/ repo root:  bash scripts/verify-event-date-backfill.sh
# Exit 0 = every assertion passed.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_ID="$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' supabase/config.toml)"
CONTAINER="supabase_db_${PROJECT_ID}"
SCRATCH_DB="event_date_backfill_check"
TARGET="20260920184837_event_date_per_event.sql"

psql_admin() { docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_scratch() { docker exec -i "$CONTAINER" psql -U postgres -d "$SCRATCH_DB" -v ON_ERROR_STOP=1 -q "$@"; }

cleanup() { psql_admin -c "drop database if exists ${SCRATCH_DB} with (force)" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

psql_admin -c "create database ${SCRATCH_DB}"

# Minimal stand-in for Supabase's auth.users (profiles FKs to it).
psql_scratch -c "
  create schema auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb);
"

for file in supabase/migrations/*.sql; do
  [ "$(basename "$file")" = "$TARGET" ] && break
  psql_scratch -1 < "$file"
done

# Legacy-shaped data (event_date does not exist yet, service_date does).
psql_scratch <<'SQL'
insert into public.clients (id, name) values ('11111111-1111-1111-1111-111111111111', 'Legacy Client');
insert into public.event_types (id, name) values ('22222222-2222-2222-2222-222222222222', 'Legacy Type');

-- E1: hourly services on two different legacy dates + a unit service -> earliest date wins.
-- E2: unit-billed services only -> falls back to created_at::date.
-- E3: no services at all -> falls back to created_at::date.
-- E4: one hourly service -> that service's date.
insert into public.events (id, client_id, event_type_id, location, created_at, updated_at) values
  ('e1e1e1e1-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'E1', '2026-05-01 12:00+00', '2026-05-02 08:00+00'),
  ('e2e2e2e2-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'E2', '2026-01-15 12:00+00', '2026-01-16 09:00+00'),
  ('e3e3e3e3-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'E3', '2026-04-20 12:00+00', '2026-04-21 10:00+00'),
  ('e4e4e4e4-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'E4', '2026-02-10 12:00+00', '2026-02-11 11:00+00');

insert into public.event_services (event_id, service_type, service_date, start_time, end_time, price_per_hour) values
  ('e1e1e1e1-0000-0000-0000-000000000001', 'fotografias', '2026-03-10', '10:00', '12:00', 100),
  ('e1e1e1e1-0000-0000-0000-000000000001', 'entrevistas', '2026-02-01', '09:00', '10:00', 80),
  ('e4e4e4e4-0000-0000-0000-000000000004', 'anuncios', '2026-07-04', '18:00', '19:00', 50);
insert into public.event_services (event_id, service_type, price_per_unit, quantity) values
  ('e1e1e1e1-0000-0000-0000-000000000001', 'fotos_impresas', 10, 3),
  ('e2e2e2e2-0000-0000-0000-000000000002', 'fotos_enmarcadas', 20, 2);
SQL

# Apply the migration under test as ONE transaction (-1), exactly like the CLI.
psql_scratch -1 < "supabase/migrations/${TARGET}"

RESULT="$(psql_scratch -At -F '|' <<'SQL'
select left(location, 2), event_date::text, (updated_at = case location
    when 'E1' then '2026-05-02 08:00+00'::timestamptz
    when 'E2' then '2026-01-16 09:00+00'::timestamptz
    when 'E3' then '2026-04-21 10:00+00'::timestamptz
    when 'E4' then '2026-02-11 11:00+00'::timestamptz end)::text
from public.events order by location;
SQL
)"

EXPECTED="E1|2026-02-01|true
E2|2026-01-15|true
E3|2026-04-20|true
E4|2026-07-04|true"

echo "event | event_date | updated_at preserved"
echo "$RESULT"

if [ "$RESULT" != "$EXPECTED" ]; then
  echo "FAIL: backfill result differs from expected:" >&2
  echo "$EXPECTED" >&2
  exit 1
fi

# Schema after the migration: column gone, not-null/index present, service rows intact.
AFTER="$(psql_scratch -At <<'SQL'
select
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'event_services' and column_name = 'service_date'),
  (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'event_date'),
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'events_event_date_idx'),
  (select count(*) from public.event_services);
SQL
)"

if [ "$AFTER" != "0|NO|1|5" ]; then
  echo "FAIL: post-migration schema check expected '0|NO|1|5', got '${AFTER}'" >&2
  exit 1
fi

echo "OK: backfill = earliest service_date, else created_at::date; updated_at preserved; schema as expected."
