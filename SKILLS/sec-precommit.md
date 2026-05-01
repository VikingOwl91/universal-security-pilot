# sec-precommit — Wave 0: Pre-Commit Gating (Shift-Left)

> **STATUS: v3.1 SCAFFOLDING STUB.** This skill is not operational. Do not invoke `/sec-precommit` against a project until this file is filled in and the canonical pilot version is cut from `3.1.0-alpha` to a non-alpha `3.1`. Until then, the pilot operates under v3.0 (W1–W4) only.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 0 is the **Shift-Left entry point** of the framework. It runs *before* the agent can call `git commit` on an artifact that W1–W4 would later have to audit. A committed secret cannot be audited out — it has to never reach the commit. W0 enforces that gate at the local hook layer, before any push, before any CI run, before any later wave.

Successful W0 enforcement is a **prerequisite** for W1. If a pre-commit gate would have blocked a finding, the gate is the fix; the audit row for the finding reduces to "ensure the gate is configured and unbypassable in normal flow."

## What this skill will produce *(when filled in)*

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-precommit.md` with:

- An inventory of pre-commit hooks present, missing, or bypassed in the project.
- A scan of git history for evidence of bypass (`--no-verify`, force-pushed amends over hook-rejected commits, hooks disabled in CI but not locally).
- A list of secret-scan, policy-lint, and blocked-pattern rules the project should add or harden, each citing OWASP / ASVS / CWE.
- Remediation steps mapped to the Wave Protocol — every W0 fix ships with its own failing PoC test per the Iron Law (e.g., a test that commits a known-bad payload and asserts the hook rejects it).

## Scope (when active)

- Pre-commit hook framework selection and pinning (`pre-commit`, `husky`, `lefthook`, native git hooks).
- Secret scanning at the hook stage (gitleaks, trufflehog, custom regex packs) — **never** as the only line of defense; pairs with PILOT §5 secret hygiene.
- Policy-lint of artifacts the commit would introduce (Dockerfile lint, Helm values lint, Terraform plan diffs, `.env` accidental-stage detection).
- Blocked-pattern denial: literal-string lists derived from the project's own canonical-pattern catalog, applied via the pre-commit hook before the commit object is written.
- Bypass-resistance: hooks must be enforced server-side (in CI / branch-protection) so a local `--no-verify` does not ship to the protected branch.

## Out of scope

- Server-side secret rotation (that is W3 — secret hygiene under PILOT §5).
- Runtime egress policy (that is W2 / W5 / W6 depending on layer).
- IDE-level inline linting (different layer; complementary, not equivalent).

## Iron Law applies recursively

Every Wave 0 control must ship with a failing PoC test that proves the gate would block the bad input, then passes after the gate is wired. A pre-commit hook claiming to block a secret pattern, with no test that *attempts* to commit that pattern and asserts rejection, is not an enforced control — it is wishful configuration.

## TODO before this skill goes operational

1. Citation map: every W0 finding row maps to OWASP / ASVS / CWE IDs. Draft the row template and validate against `PILOT.md` Compliance Stack.
2. PoC-test recipes for the three highest-volume W0 categories (committed-secret, malformed-Dockerfile, plaintext-Helm-secret).
3. Bypass-resistance audit checklist: how to prove server-side enforcement matches the local hook.
4. Adapter notes: how `pre-commit`, `husky`, and `lefthook` differ in failure-mode and which is recommended per stack.
5. Cut canonical pilot from `3.1.0-alpha` to `3.1` once items 1–4 are filled in and reviewed.
