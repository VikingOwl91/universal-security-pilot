---
title: Framework Footgun Library
parent: Universal Security Pilot v3.0 (~/.security-pilot/PILOT.md)
purpose: Stack- and framework-specific recurring footguns, beyond the language-level table in PILOT §2
audit-rule: When a finding involves a framework covered here, cite the matching footgun ID alongside the standard OWASP/ASVS/CWE IDs
---

# Framework Footgun Library

Catalogue of recurring framework-specific footguns. Grows over time. Audits MUST consult this file when a covered framework is in scope.

Each entry uses the format:

```
### F-<framework-slug>-<n> — <one-line title>
**Maps to:** OWASP A0X · ASVS V0X.X · CWE-XX · (LLM0X / AML.TXXXX where applicable)
**Symptom in code:** <what the audit looks for>
**Why it's wrong:** <one paragraph>
**Canonical fix:** <pattern from PILOT.md if one applies, else direct fix shape>
**PoC test shape:** <one-line failing-test description>
```

---

## SvelteKit / Node

SvelteKit ships with strong defaults but several surfaces silently fall back to insecure behavior when the deployment topology isn't fully described to the framework. Adapter-node specifically hands several decisions to environment variables that are easy to leave unset.

### F-svelte-1 — CSRF protection bypassed on JSON endpoints
**Maps to:** OWASP A01 · ASVS V4.2.2 · CWE-352
**Symptom in code:** A `+server.ts` handler with `POST`, `PUT`, `PATCH`, `DELETE` that returns JSON, where the project relies on session cookies for auth and `kit.csrf.checkOrigin` is disabled or the framework version's default has changed.
**Why it's wrong:** SvelteKit's `csrf.checkOrigin` validates the `Origin` header only against form-encoded requests by default in older versions; JSON `Content-Type: application/json` requests historically slipped through. Even when `checkOrigin: true`, a missing `Origin` header (some embedded clients) can be treated permissively. Cross-site JSON POST + cookie auth = classic CSRF.
**Canonical fix:** Enforce both: (a) `csrf.checkOrigin: true` in `svelte.config.js`; (b) explicit `Origin`/`Referer` allowlist check in every state-changing handler; (c) cookies set `SameSite=Strict` for session cookies (or `Lax` only if the flow truly requires top-level navigation). For browser-API-token flows, require a custom header (`X-Requested-With` or a CSRF token) the browser cannot set cross-origin without preflight.
**PoC test shape:** `Test: cross-origin POST with Content-Type=application/json and an attacker Origin header is rejected with 403 — does not execute the side effect.`

### F-svelte-2 — SSRF via env-derived fetch in `load`/`+server.ts` (server-side)
**Maps to:** OWASP A10 · ASVS V12.6.1 · CWE-918
**Symptom in code:** Server-side handler using `fetch(env.UPSTREAM_BASE + userPath)` or `fetch(\`${env.SOMETHING}/\${input}\`)`, including SvelteKit's special `event.fetch`. Or worse: `fetch(userControlledUrl)`.
**Why it's wrong:** SvelteKit's server runtime executes inside the same network namespace as the application — it can reach localhost, the cluster service mesh, and cloud-metadata endpoints (`169.254.169.254`). Env vars are *not* a trust boundary: a misconfigured `UPSTREAM_BASE` (say, set to `http://localhost:8500/v1/kv/`) plus a user-controlled path becomes a key-value-store reader.
**Canonical fix:** **Dial-Control** for Node (PILOT.md "Dial-Control — Node.js / TypeScript" — use `https.Agent` with `lookup` hook, or undici `Agent` with `connect.lookup`, blocking RFC 1918 / loopback / link-local / IPv6 ULA / metadata IPs). Plus an explicit hostname allowlist read at startup, validated against config schema, and rejected if loopback or RFC1918 hostnames slip in.
**PoC test shape:** `Test: a request whose user-controlled path resolves to http://169.254.169.254/... fails with ESSRF — never reaches the metadata endpoint.`

### F-svelte-3 — adapter-node deployed without `BODY_SIZE_LIMIT`, `ORIGIN`, `XFF_DEPTH`
**Maps to:** OWASP A05 · ASVS V14.1.1 / V13.1.5 · CWE-770 / CWE-348
**Symptom in code:** A SvelteKit project using `@sveltejs/adapter-node` with no `BODY_SIZE_LIMIT`, no `ORIGIN`, no `PROTOCOL_HEADER`/`HOST_HEADER`/`XFF_DEPTH` set in the runtime environment.
**Why it's wrong:**
- `BODY_SIZE_LIMIT` unset → adapter-node will buffer arbitrary request bodies; trivially DoS-able.
- `ORIGIN` unset → SvelteKit cannot validate request origin against an authoritative same-origin string; CSRF protection becomes guesswork (especially behind a reverse proxy that rewrites `Host`).
- `PROTOCOL_HEADER` unset → `cookies.set({ secure: true })` may misbehave because `event.url.protocol` is not derivable correctly.
- `XFF_DEPTH` wrong (default `0`) → `event.getClientAddress()` returns the first hop, which is the proxy or the attacker's spoofed `X-Forwarded-For`. IP-based rate limits and audit logs become attacker-controlled.
**Canonical fix:** In the deployment manifest (Helm, Compose, systemd unit, etc.), set:
- `BODY_SIZE_LIMIT=524288` (512 KB; tune per route — consider per-route cap via middleware for upload endpoints).
- `ORIGIN=https://your.canonical.host`
- `PROTOCOL_HEADER=x-forwarded-proto`
- `HOST_HEADER=x-forwarded-host`
- `XFF_DEPTH=<N>` where N matches the trusted proxy chain (e.g., 1 if behind a single ingress controller; 2 behind ingress + CDN).
- Document the deployment topology in `<project>/.security-pilot/PROJECT_PILOT.md` so reviewers can verify N.
**PoC test shape:** `Test: request with X-Forwarded-For: attacker-controlled, behind 1-hop proxy with XFF_DEPTH=1 → getClientAddress() returns the trusted proxy's view, not the attacker's spoof.`

### F-svelte-4 — Server-only modules accidentally imported into client bundle
**Maps to:** OWASP A02 / A05 · ASVS V14.3.3 · CWE-200
**Symptom in code:** A file under `src/lib/` (no `$server` suffix) that imports `node:fs`, `node:crypto` private-key code, or environment secrets — and is imported by a `+page.svelte` or `+page.ts`.
**Why it's wrong:** SvelteKit will attempt to bundle that file for the client. Vite normally errors on Node built-ins, but `process.env.SECRET` references can leak into the client bundle if pulled in via a re-export chain. The result is secrets shipped to the browser.
**Canonical fix:** Use `$lib/server/` (or `$server` suffix) for any module that touches `node:*`, `$env/static/private`, `$env/dynamic/private`, or any secret. Add an ESLint / `vite-plugin-checker` rule. Run `vite build` and grep the client bundle for known secret prefixes (`sk_live_`, `AKIA`, etc.) as a CI smoke-test.
**PoC test shape:** `Test: vite build emits no client-bundle artifact containing the literal value of any private env var.`

### F-svelte-5 — Form actions returning unsanitized data into HTML render
**Maps to:** OWASP A03 · ASVS V5.3.3 · CWE-79 · LLM02 (when AI-generated)
**Symptom in code:** A form action returning `{ message: aiOrUserDerivedString }` and a `+page.svelte` rendering `{@html data.message}`.
**Why it's wrong:** `{@html …}` is the SvelteKit raw-HTML escape hatch. Equivalent risk profile to React's raw-HTML escape-hatch prop. Any unsanitized model output or stored user content becomes XSS.
**Canonical fix:** Default to `{data.message}` (text node). If markup is required, render through DOMPurify with a tight allowlist (see PILOT §6 Output Sanitizer + the ai-harden checklist).
**PoC test shape:** `Test: form action returning '<img src=x onerror=alert(1)>' renders as plain text in the DOM; no script execution.`

---

## Drizzle ORM

Drizzle's design is correct — `sql\`\`` template tags parameterize automatically — but several escape hatches and developer workflows reintroduce injection or schema-drift risk.

### F-drizzle-1 — `sql.raw()` with user-derived input
**Maps to:** OWASP A03 · ASVS V5.3.4 · CWE-89
**Symptom in code:** Any `sql.raw(...)` whose argument is a string built from user input, or `db.execute(sql.raw(\`SELECT … \${userInput}\`))`.
**Why it's wrong:** `sql.raw()` deliberately bypasses Drizzle's parameterizer; the string is sent to the driver verbatim. Any user input concatenated into that string is direct SQL injection.
**Canonical fix:** Use the `sql\`\`` template tag for parameterized values (`sql\`SELECT * FROM users WHERE id = \${userId}\`` — Drizzle binds `userId` as a parameter, not a string substitution). For dynamic identifiers (column or table names that need to come from input), use `sql.identifier(name)` after validating `name` against an allowlist of known identifiers. Never validate-by-regex on identifier names — use an explicit allowlist.
**PoC test shape:** `Test: query built from input "1; DROP TABLE users;--" executes as a parameterized literal, not as a separate statement; users table still exists.`

### F-drizzle-2 — Raw `database.execute()` for migrations bypassing the migrator
**Maps to:** OWASP A05 · ASVS V14.1.5 · CWE-1188
**Symptom in code:** A migration script that calls `database.execute(rawDdlString)` directly (or `db.run(rawDdlString)` in the SQLite driver) instead of using `drizzle-kit`'s migration files.
**Why it's wrong:** Bypasses migration-history tracking. A migration that ran on staging but not prod is invisible. Re-running idempotently is up to the developer (often broken). DDL with secrets baked in (default values containing API keys, etc.) bypasses any review meant to catch them.
**Canonical fix:** Use `drizzle-kit generate` (creates versioned migration files in `drizzle/`) and `drizzle-kit migrate` (applies them with history tracking). Code review every migration. For one-off ops queries, use a separate ops-run path that requires elevated credentials and logs to an audit table — not the application's migration runner.
**PoC test shape:** `Test: drizzle-kit migrate runs cleanly twice in a row on a clean DB (idempotency), and the schema after second run equals the schema after first run.`

### F-drizzle-3 — `drizzle-kit push` against production
**Maps to:** OWASP A05 · ASVS V14.1.4 · CWE-1188
**Symptom in code:** A CI/CD pipeline or deploy script that runs `drizzle-kit push` against a production database URL, or any `npm run db:push` script whose target depends on environment.
**Why it's wrong:** `drizzle-kit push` syncs schema-from-code to the database without writing migration files. Convenient for local dev; catastrophic for production — a renamed column gets dropped and recreated, losing data. Schema-drift between environments goes undetected.
**Canonical fix:** Restrict `push` to local development databases only. CI/CD uses `drizzle-kit generate` (in dev) → review → commit migration file → `drizzle-kit migrate` (in deploy). Add a hard guard in `package.json` scripts that refuses to run `push` if `NODE_ENV=production` or if the target URL hostname is in a production allowlist.
**PoC test shape:** `Test: invoking the push script with a production-URL env var exits non-zero with "production target rejected" before any DDL runs.`

### F-drizzle-4 — Migration files committed with embedded secrets
**Maps to:** OWASP A02 · ASVS V14.1.4 / V8.3.4 · CWE-798
**Symptom in code:** A generated migration `.sql` file under `drizzle/` containing literal API keys, OAuth client secrets, or DB connection strings as default values for new columns or seed-data inserts.
**Why it's wrong:** Migration files are committed to the repo. Embedded secrets are now in git history forever. Even if the migration runs and the column is later dropped, `git log -p` reveals the secret.
**Canonical fix:** Migrations contain only schema. Seed data goes through a separate seeder that reads secrets at runtime from KMS / Vault / env. Add a pre-commit hook that scans `drizzle/*.sql` for known secret patterns (`sk_live_`, `AKIA`, JWT shapes, postgres URL with creds). Pair with `git-secrets` or `gitleaks` in CI.
**PoC test shape:** `Test: every committed migration file passes the secret-scanner; CI fails if a pattern is found.`

### F-drizzle-5 — `db.transaction()` with mixed reads outside the transaction
**Maps to:** OWASP A04 · ASVS V1.11.2 · CWE-362
**Symptom in code:** A handler that reads a value with `db.select()...` *outside* a transaction, branches on it, then writes inside `db.transaction(...)` — the classic check-then-act race (PILOT §4).
**Why it's wrong:** The read is at the default isolation level (probably READ COMMITTED in Postgres), the transaction is at the same level, and the gap between them is fully concurrent. Two clients can both read "balance ≥ amount" and both debit successfully.
**Canonical fix:** Move the read *into* the transaction with `SELECT ... FOR UPDATE` (Drizzle: `.for("update")`), or replace the read-then-branch-then-write with a single conditional `UPDATE` (PILOT §4 atomic-UPDATE pattern). Verify with a real-DB concurrency test using the project test harness — never with mocks.
**PoC test shape:** `Test: N concurrent goroutines/promises each debit amount from a balance seeded with N*amount-1; exactly one fails with insufficient-funds; final balance is non-negative.`

---

## How to extend this library

When you encounter a recurring framework-specific footgun during an audit:
1. Open this file.
2. Pick the next ID under the relevant framework (or add a new H2 section if the framework is new).
3. Use the format at the top of this document.
4. Reference the matching standard IDs and the canonical pilot pattern (or "no canonical pattern" + a direct fix shape).
5. Commit alongside the audit report that surfaced the pattern.

The library should be biased toward **footguns that recur across projects**, not project-specific quirks. A project-specific recurring issue belongs in `<project>/.security-pilot/PROJECT_PILOT.md`.
