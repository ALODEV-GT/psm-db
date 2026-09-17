#!/usr/bin/env node
// Node-level assertion script — this project has no JS test runner
// configured yet, so this is a plain `node`-invoked script using the
// built-in `node:assert/strict` module, checked for correct exit behavior.
//
// Proves scripts/seed-dev-data.mjs's loopback guard aborts BEFORE any write
// when the resolved Supabase URL is not 127.0.0.1/localhost (design.md
// "Threat Matrix" — Subprocess: execFile with argv array, shell:false,
// loopback-only URL guard before any write, service-role key never logged).
//
// Run: node scripts/seed-dev-data.guard.test.mjs
// Exit code 0 = every assertion passed. A thrown AssertionError (non-zero
// exit) means a regression in the guard.

import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.join(__dirname, "seed-dev-data.mjs");

// --- Unit-level assertions: import the guard function directly ---
const { assertLoopbackUrl } = await import(scriptPath);

assert.doesNotThrow(
  () => assertLoopbackUrl("http://127.0.0.1:54321"),
  "assertLoopbackUrl must accept a 127.0.0.1 URL",
);
assert.doesNotThrow(
  () => assertLoopbackUrl("http://localhost:54321"),
  "assertLoopbackUrl must accept a localhost URL",
);
assert.throws(
  () => assertLoopbackUrl("https://evil.example.com"),
  /loopback/i,
  "assertLoopbackUrl must reject a non-loopback URL",
);

console.log(
  "PASS: assertLoopbackUrl unit assertions (loopback accepted, non-loopback rejected)",
);

// --- Subprocess-level assertion: the real script aborts BEFORE any write ---
// SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY env overrides skip the internal
// `supabase status -o env` subprocess entirely, so this proves the guard
// fires deterministically without depending on a running Supabase instance.
const SENTINEL_KEY = "sentinel-service-role-key-never-logged";

const result = await new Promise((resolve) => {
  execFile(
    process.execPath,
    [scriptPath],
    {
      shell: false,
      timeout: 5000,
      env: {
        ...process.env,
        SUPABASE_URL: "https://not-loopback.example.com",
        SUPABASE_SERVICE_ROLE_KEY: SENTINEL_KEY,
      },
    },
    (error, stdout, stderr) => {
      resolve({ code: error ? (error.code ?? 1) : 0, stdout, stderr });
    },
  );
});

assert.notEqual(
  result.code,
  0,
  "seed script must exit non-zero when the resolved URL is not loopback",
);

const combinedOutput = `${result.stdout}${result.stderr}`;
assert.match(
  combinedOutput,
  /loopback/i,
  "seed script must report the loopback guard failure",
);
assert.doesNotMatch(
  combinedOutput,
  new RegExp(SENTINEL_KEY),
  "seed script must never log the service-role key",
);

console.log(
  "PASS: seed-dev-data.mjs aborts before any write for a non-loopback SUPABASE_URL",
);
console.log("All loopback-guard assertions passed.");
