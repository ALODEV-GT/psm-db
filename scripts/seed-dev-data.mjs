#!/usr/bin/env node
// Node seed script — owns everything downstream of auth.users (design.md
// D1/D2). supabase/seed.sql only seeds user-independent lookups; GoTrue's
// admin create-user endpoint does not accept a caller-supplied id, so
// anything FK'd to profiles can only be inserted at runtime, after the
// Admin API resolves real UUIDs.
//
// Threat matrix (design.md "Threat Matrix" — Subprocess, not in the
// reference matrix but applicable here): this script spawns
// `supabase status -o env` via execFile with an argv array and
// `shell: false` (never a shell string), and refuses to write anything
// unless the resolved Supabase URL is a loopback address. The service-role
// key is never logged or persisted to disk.
//
// Domain-data helpers (client/event/service/closure inserts) live in
// ./lib/seed-domain-data.mjs — this file stays scoped to credential
// resolution, the loopback guard, and orchestration.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createClient } from "@supabase/supabase-js";
import { pathToFileURL } from "node:url";
import {
  createUsers,
  fetchLookupId,
  seedClients,
  seedClosedEvent,
  seedOpenEvent,
} from "./lib/seed-domain-data.mjs";

const execFileAsync = promisify(execFile);

const LOOPBACK_HOSTNAMES = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);

export class NonLoopbackSupabaseUrlError extends Error {
  constructor(rawUrl) {
    super(
      `Refusing to seed: resolved Supabase URL "${rawUrl}" is not a loopback ` +
        "address (127.0.0.1/localhost). Seeding must target a local Supabase " +
        "instance only.",
    );
    this.name = "NonLoopbackSupabaseUrlError";
  }
}

/**
 * Guard: throws NonLoopbackSupabaseUrlError unless `rawUrl`'s hostname is a
 * loopback address. Never inspects or logs credentials — URL only. MUST be
 * called before any Supabase client is created or any write is attempted.
 */
export function assertLoopbackUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new NonLoopbackSupabaseUrlError(rawUrl);
  }
  if (!LOOPBACK_HOSTNAMES.has(parsed.hostname)) {
    throw new NonLoopbackSupabaseUrlError(rawUrl);
  }
  return parsed;
}

function parseEnvOutput(stdout) {
  const values = {};
  for (const line of stdout.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="(.*)"$/);
    if (match) {
      values[match[1]] = match[2];
    }
  }
  return values;
}

/**
 * Resolves { url, serviceRoleKey }. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
 * env vars override and skip the subprocess entirely; otherwise shells out
 * to `supabase status -o env` via execFile (argv array, shell: false — no
 * string interpolation, no committed key).
 */
export async function resolveSupabaseCredentials() {
  if (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return {
      url: process.env.SUPABASE_URL,
      serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    };
  }

  const { stdout } = await execFileAsync(
    "supabase",
    ["status", "-o", "env"],
    { shell: false },
  );
  const values = parseEnvOutput(stdout);
  if (!values.API_URL || !values.SERVICE_ROLE_KEY) {
    throw new Error(
      "Could not resolve API_URL/SERVICE_ROLE_KEY from `supabase status -o env`. " +
        "Is the local Supabase stack running (`npm run db:start`)?",
    );
  }
  return { url: values.API_URL, serviceRoleKey: values.SERVICE_ROLE_KEY };
}

async function main() {
  const { url, serviceRoleKey } = await resolveSupabaseCredentials();
  // Guard runs BEFORE any Supabase client is created or any write happens.
  assertLoopbackUrl(url);

  const supabase = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // No-op guard: a non-empty profiles table means this has already run
  // against this database, so a re-run without `db reset` is a no-op.
  const { count, error: countError } = await supabase
    .from("profiles")
    .select("id", { count: "exact", head: true });
  if (countError) throw countError;
  if (count && count > 0) {
    console.log("Seed skipped: profiles table is already populated.");
    return;
  }

  const profileIds = await createUsers(supabase);
  const { ramirezId, garciaId } = await seedClients(supabase, profileIds.admin);
  const [bodaTypeId, cumpleanosTypeId] = await Promise.all([
    fetchLookupId(supabase, "event_types", "Boda"),
    fetchLookupId(supabase, "event_types", "Cumpleaños"),
  ]);

  await seedOpenEvent(supabase, {
    adminId: profileIds.admin,
    tecnicoId: profileIds.tecnico,
    usuarioId: profileIds.usuario,
    clientId: ramirezId,
    eventTypeId: bodaTypeId,
  });

  await seedClosedEvent(supabase, {
    adminId: profileIds.admin,
    clientId: garciaId,
    eventTypeId: cumpleanosTypeId,
  });

  console.log("Seed complete: 3 users, 2 clients, 2 events (1 open, 1 closed).");
}

const isMainModule =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
  main().catch((error) => {
    // Only the error message is ever logged — never the full error object,
    // which could otherwise surface request headers containing the key.
    console.error(error.message);
    process.exitCode = 1;
  });
}
