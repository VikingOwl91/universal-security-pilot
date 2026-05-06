---
name: sec-audit
description: Run a merciless zero-trust security audit (OWASP / ASVS L2 / OWASP LLM / MITRE ATLAS / CWE-mapped) on a branch, file, or scope. Produces a structured Markdown report under .security-pilot/audits/. Invoke as `$sec-audit [scope]`.
---

# sec-audit — Universal Security Pilot

Run a zero-trust security audit driven by the canonical Universal Security Pilot v3.0 skill. The skill body below is a thin wrapper: read the canonical files in full and follow them exactly.

## Required reads (load before any audit work)

1. `~/.security-pilot/PILOT.md`
2. `~/.security-pilot/SKILLS/sec-audit.md`
3. `~/.security-pilot/COMMANDS/sec-audit.md`

If a project-local `<project>/.security-pilot/PROJECT_PILOT.md` exists, also read it. The canonical `PILOT.md` wins on any conflict.

## Scope

The user invokes this skill with `$sec-audit [scope]`:

- Path argument → audit that file or directory.
- Literal token `branch`, or no argument → audit the full diff between the current git branch and the default branch (`main` / `master`).

## Procedure

Follow `COMMANDS/sec-audit.md` exactly:

- Walk the eight rules from `PILOT.md`.
- Produce the report using the template in `SKILLS/sec-audit.md`.
- Resolve the output path per Step 4 of the command (project-local audits dir preferred; create it if missing; fall back to `~/.security-pilot/audits/`).

## Hard rules

- Every finding cites at least one OWASP / ASVS / LLM / ATLAS / CWE ID.
- No fix suggestions without a reproducible PoC plan (Iron Law).
- Wave order: W1 auth/identity → W2 network → W3 data/secrets → W4 UI/output. Never out of order.
