# database

Supabase (Postgres) local dev stack for proyecto1 (Producciones Santa María).

This repo owns the schema only: 11 SQL migrations, RLS, a pgTAP test suite,
and seed data. It has no backend or frontend code, and is meant to be
verified completely on its own before `backend-api` (a separate repo/change)
starts consuming it.

## Prerequisites

- **Docker**, running. The Supabase CLI drives a local stack (Postgres,
  GoTrue, PostgREST, Studio, Storage, Realtime, ...) entirely through Docker
  Compose — there is no hand-rolled Postgres container here.
- **Node.js**, selected via [`nave`](https://github.com/isaacs/nave) using
  the version pinned in `.node-version`. Never install anything for this
  project with `npm install -g`. The Supabase CLI itself is **not** a global
  tool: it is a local `devDependency` (`package.json`) invoked through `npx`
  or the `npm run db:*` scripts, which also happens to be the only way its
  own npm package supports installation (it refuses a global install).

## Setup

```bash
npm install
npm run db:start      # or: npx supabase start
npm run db:setup      # supabase db reset (applies all 11 migrations + seed.sql)
                       # + scripts/seed-dev-data.mjs (auth users + sample domain data)
```

`npm run db:start` boots the full local stack (Postgres on `54322`, the REST
API on `54321`, Studio on `54323`, Inbucket/Mailpit for local email capture
on `54324`). `npm run db:setup` runs `db:reset` (all 11 migrations plus the
lookup-table seed in `supabase/seed.sql`) and then `db:seed`
(`scripts/seed-dev-data.mjs`), which creates 3 auth users (admin, usuario,
tecnico) via the Supabase Admin API and a small set of sample
clients/events/services under them. `db:seed` is idempotent — re-running it
against an already-seeded database is a no-op (it checks whether `profiles`
already has rows).

### Available scripts

| Script | What it does |
|---|---|
| `npm run db:start` | Boots the local Supabase stack |
| `npm run db:stop` | Stops it |
| `npm run db:reset` | Drops and recreates the local DB, applies all migrations + `seed.sql` |
| `npm run db:seed` | Runs `scripts/seed-dev-data.mjs` (auth users + sample domain data) |
| `npm run db:setup` | `db:reset && db:seed` — the full clean-slate setup |
| `npm run db:diff` | Diffs the running DB against migrations (`supabase db diff`) |
| `npm run db:test` | Runs the full pgTAP suite (`supabase test db`) |
| `npm run migration:new` | Scaffolds a new timestamped migration file |

### Credentials for `scripts/seed-dev-data.mjs`

The seed script needs a Postgres/Supabase URL and the **service-role** key
(it bypasses RLS on purpose — see "Security model" below). By default it
resolves both automatically from `npx supabase status -o env` against the
running local stack. Overriding is optional: setting the `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` environment variables before running `npm run
db:seed` takes precedence over the auto-resolved values. The script hard-
refuses to run against a non-loopback URL, and never logs the key, so it is
safe to run repeatedly against local dev.

## Security model

**RLS is a default-deny safety net. It is not the authorization boundary.**

Every one of the 14 domain tables has row-level security **enabled with
zero policies**, plus an explicit `revoke all on <table> from anon,
authenticated`. Concretely: an anonymous or `authenticated`-role query
against any table is rejected outright (Postgres `42501: permission
denied`, surfaced by PostgREST as an HTTP error) — not silently filtered to
an empty result set. `supabase/tests/12_rls_default_deny.test.sql` proves
this for all 14 tables in one pass by executing each query as the `anon`
role, the same role PostgREST assumes per-request for the anon API key.

This exists purely as a backstop — a bug in the backend, a leaked anon key,
or someone querying PostgREST directly should never be able to read or
write anything. It is **not** how this project does authorization.

The real authorization boundary lives one layer up, in the Express backend
(a separate repo/change, `backend-api`): the backend connects to Postgres
using the **service-role key**, which has `BYPASSRLS` and therefore ignores
every RLS check on every table. All actual access control — who can see
which client, who can close an event, role checks against `profiles.role`
(`admin` / `usuario` / `tecnico`) — is enforced in the Express **service**
layer (see `back-architecture`), never in the database. Do not add RLS
policies here expecting them to carry authorization logic; they will never
run for the backend's own queries, and the intent of this schema is that
they don't need to.

The one exception where the database *does* enforce a business rule
directly is data-integrity, not authorization: `handle_new_user()`
(migration `..._profiles.sql`) creates a `profiles` row for every new
`auth.users` row and hardcodes its `role` to `usuario`, because `auth.users`
has write paths outside Express (GoTrue, Studio, this repo's own seed
script) that a service-layer check could never intercept. That is a
DB-enforced invariant, not a policy-based authorization decision.

## Verification

These are the checks this repo must pass on a clean clone, with Docker
running, before any backend work depends on it:

```bash
npm install
npx supabase start                 # boots cleanly
npx supabase db reset              # applies all 11 migrations, zero errors
npx supabase db reset              # run a second time: idempotent, identical schema
npm run db:setup && npm run db:test   # full pgTAP suite green
```

`npm run db:test` runs 13 pgTAP files covering: every table's expected
columns/constraints/FKs, the polymorphic `event_services` CHECK math
(hourly vs. unit pricing), the D10 livestream-child gating (platform/phone
rows can only attach to a `transmision_en_vivo` service), the generated
`subtotal`/`net_result` columns, the reporting views, `seed.sql`
idempotency, and the whole-schema RLS default-deny proof described above.

You can also confirm Studio (`http://127.0.0.1:54323` by default) shows all
14 tables plus the 3 reporting views, RLS enabled on every table, and the
seeded sample data (2 clients, 2 events — one of them multi-service with a
`transmision_en_vivo` service linked to 2 platforms and 2 phone numbers,
plus one fully closed event with collaborators/expenses/a closure row).

## Rollback

The whole schema was delivered as a chain of independently reviewable PRs
(scaffold → migrations 00-02 → 03-05 → D10 livestream gating → 07-08 →
09-10 → seeding → this doc/verification PR). Reverting any single PR and
re-running `npx supabase db reset` cleanly rolls that slice back, since each
migration only adds objects the later ones depend on. Reverting everything
is `rm -rf database/` — nothing outside this repo depends on it yet.
