-- Seed: lookup tables only (event_types, platforms, expense_types).
-- Auto-run by `supabase db reset` (config.toml [db.seed] sql_paths). This
-- file MUST NOT touch the `auth` schema or any table FK'd to
-- auth.users/profiles: GoTrue's admin create-user endpoint does not accept
-- a caller-supplied id, so anything downstream of profiles can only be
-- inserted at runtime, after real UUIDs are known (design.md D1/D2). That
-- data is seeded by scripts/seed-dev-data.mjs (`npm run db:seed`) instead.
--
-- Idempotent via ON CONFLICT on each table's case-insensitive unique name
-- index (migration 02_lookup_tables), so re-running `db reset` never
-- duplicates rows.

insert into public.event_types (name) values
  ('Boda'),
  ('Cumpleaños'),
  ('Graduación'),
  ('Quinceañera'),
  ('Corporativo')
on conflict (lower(name)) do nothing;

insert into public.platforms (name) values
  ('Facebook'),
  ('YouTube'),
  ('TikTok')
on conflict (lower(name)) do nothing;

insert into public.expense_types (name) values
  ('Internet'),
  ('Transporte'),
  ('Alimentación'),
  ('Otros')
on conflict (lower(name)) do nothing;
