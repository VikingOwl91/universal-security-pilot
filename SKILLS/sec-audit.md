# sec-audit — Zero-Trust Security Audit

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, and canonical patterns this skill cites. Findings without a pilot ID citation are invalid.

## What this skill produces

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-<scope>.md` (or `~/.security-pilot/audits/<YYYY-MM-DD>-<scope>.md` when no project root is identifiable) with the structure below. Every finding cites at least one OWASP/ASVS/LLM/ATLAS/CWE ID per the pilot.

## When to use

- "Audit this for security."
- "Review the branch before we ship."
- "Pre-deploy security check."
- A diff or PR explicitly requested for security review.
- Any new auth, identity, payments, or LLM data-flow code.

## When NOT to use

- Single-line typo fixes, dependency bumps with no behavior change, doc-only PRs.
- Performance tuning that does not cross a security boundary.
- Pure refactors with green test runs and no public API change.

## Pre-audit grounding (do this before reading code)

1. **Identify scope.** What files, what branch, what change? Treat anything outside scope as out-of-scope and note it.
2. **Identify the threat model in one paragraph.** Who is the attacker? What is the asset? What is the trust boundary you are crossing?
3. **Identify the language footguns.** Pull the relevant row from the pilot's Context-Aware Safety table.
4. **Confirm the standards mix.** Web app → OWASP Top 10 + ASVS L2. AI/LLM-touching code → also OWASP LLM Top 10 + MITRE ATLAS. Multilingual user surface → also pilot §8 Multilingual Defense.
5. **Walk the Universal Footgun Library — Architectural Behaviors** (PILOT.md). All four categories — A (SSR/Templating), B (Data Access), C (Egress), D (State/Persistence) — apply to almost every web service. Skipping a category requires an explicit justification in the audit report ("no client-side persistence — backend-only API"). Silent skip = audit defect.
6. **Consult the Concrete Framework Catalog** at `~/.security-pilot/REFERENCE/framework-footguns.md` if any covered framework is in scope. Cited footgun IDs (e.g., `F-svelte-2`, `F-drizzle-1`) appear in the `Maps to:` line alongside OWASP/ASVS/CWE.
7. **Confirm Pre-Audit Sanity Check is clean.** Read the project's `.security-pilot/PROJECT_PILOT.md` "Pre-Audit Blockers" section. If it lists any `[CRITICAL BLOCKER: IMMEDIATE EXPOSURE]` items, **abort the audit** and tell the user to resolve them per the `/sec-init` advisory first. Auditing a repo with active immediate-exposure findings produces recommendations downstream of an already-leaked state — the audit is misleading until those are cleared.

## Audit procedure

For each file or component in scope, walk the **eight core rules** from the pilot in order. Each rule is a checklist; for each violation found, generate a finding using the template below. Do not stop at the first finding per file — produce the complete list.

| Pass | Look for |
|---|---|
| 1. Adversarial input | Every input source: HTTP body, query, header, env, file, IPC, AI output, second-order from DB. Is it parameterized / allowlisted / length-bounded at the boundary? |
| 2. Language footguns | The pilot's table for this language. SQL string-concat, type-injection, race conditions, memory bugs, unsafe deserialization, raw-HTML escape hatches with model output. |
| 3. Identity | OIDC `state`, JWT `alg` pinning, `exp`/`iss`/`aud`, `email_verified`, refresh token rotation. |
| 4. Atomicity | Read-modify-write across goroutines / async boundaries / DB transactions without a lock or atomic op. |
| 5. Secret hygiene | Secrets in source, in logs, in URLs, in `localStorage`, in cookies without `HttpOnly`. AES mode is GCM (envelope encryption), not ECB, not CBC-without-HMAC. |
| 6. AI guarding | Output sanitizer present, system/user delimited, BudgetGate present, indirect injection via tool output considered, multilingual defense present where there's a user-facing input surface. |
| 7. SSRF | Allowlist + Dial-Control on every URL fetch. DNS rebinding, redirect-escape, metadata IPs. |
| 8. Multilingual / polyglot input | If user input crosses into a model: boundary tagging, NFC normalization, zero-width strip, decode-and-re-evaluate loop, output canaries. |

## Finding template (use exactly this structure)

```markdown
### F<n> — <one-line title>

**Severity:** Critical | High | Medium | Low | Info  *(definitions in PILOT.md)*
**Maps to:** OWASP A0X · ASVS V0X.X · LLM0X · AML.T0XXX · CWE-XX
**File:** `path/to/file.ext:LINE`
**Status:** open

**Vulnerability**
What is wrong, in one paragraph. Cite the specific construct (string-concat SQL, missing `state` check, raw-HTML sink) and why it violates the cited standard.

**Exploit scenario**
Concrete attacker walkthrough: input → step → step → impact. If exploitation requires preconditions (specific role, specific endpoint, specific browser), name them. Show a payload or curl line where it fits.

**Remediation strategy**
Wave: W1 | W2 | W3 | W4  *(per PILOT.md Wave Protocol)*
The fix shape, idiomatic to the language, referencing the canonical pattern name from PILOT.md when one applies (e.g., "wrap fetch in Dial-Control", "apply BudgetGate to model call", "switch to Envelope Encryption for at-rest storage").

**Verification test**
Failing test that gates the fix (TDD-PoC). Describe the test in one sentence — the actual code goes in sec-fix.
```

## Report header (write once at top)

```markdown
# Security Audit — <scope>

**Date:** <YYYY-MM-DD>
**Branch / commit:** <branch> / <short-sha>
**Auditor:** <agent-name> via Universal Security Pilot v3.0
**Standards applied:** OWASP Top 10 (2021) · OWASP ASVS L2 · OWASP LLM Top 10 · MITRE ATLAS · CWE
**Scope:** <files / directories / what's covered>
**Out of scope:** <what was deliberately not reviewed>
**Threat model:** <one paragraph: attacker, asset, trust boundary>

## Severity summary

| # | Title | Severity | Wave | Standard IDs |
|---|-------|----------|------|--------------|
| F1 | … | Critical | W1 | A03, ASVS V5.3.4, CWE-89 |

## Findings

<F1, F2, … per template above>

## Suggested remediation order

Per PILOT.md Wave Protocol: W1 → W2 → W3 → W4. Within wave, blast-radius descending.

1. F<x> (W1, Critical) — …
2. F<y> (W1, High) — …
…

## Tests to write first (TDD-PoC list)

- F<x>: <one-line failing-test description>
…
```

## Output path resolution

```
project_root = <result of: git rev-parse --show-toplevel, or directory of detected manifest>

if exists("$project_root/.security-pilot/audits/"):
    write to "$project_root/.security-pilot/audits/<DATE>-<scope-slug>.md"
elif exists("$project_root/.security-pilot/"):
    create "$project_root/.security-pilot/audits/" and write there
elif project_root identifiable:
    create "$project_root/.security-pilot/audits/" and write there
else:
    write to "~/.security-pilot/audits/<DATE>-<scope-slug>.md"
```
`<scope-slug>` is a kebab-case identifier (e.g., `2026-05-01-payments-api-branch.md`).

## Anti-patterns this skill rejects

- A finding without a standard ID. "Looks bad" is not a finding.
- A severity that doesn't match the definition table in PILOT.md. Use the rubric, not intuition.
- An exploit scenario that says "an attacker could..." without a concrete payload or step.
- Recommending a fix without naming the wave it belongs to.
- Reporting style preferences ("magic numbers", "long function") as security findings — wrong skill.
- Skipping the OWASP LLM / MITRE ATLAS pass on code that touches an LLM.
- Skipping the multilingual pass on code that takes natural-language user input into a model.
- Force-fitting a canonical pattern (BudgetGate, Dial-Control, Envelope Encryption) where it doesn't apply.

## Common mistakes

| Mistake | Correction |
|---|---|
| Listing severities by gut feel | Use PILOT.md severity definitions verbatim |
| Skipping the standards pass on internal-only services | Internal does not mean trusted; same standards apply |
| One finding per file maximum | Produce all findings; do not artificially limit |
| Citing only OWASP, no ASVS | ASVS is mandatory at L2 — find the matching V-control |
| Citing only English-input vulnerabilities | If the input surface accepts any natural language, audit per §8 |
| Writing fix code in the audit report | Audits describe; sec-fix implements. Keep them separate. |
