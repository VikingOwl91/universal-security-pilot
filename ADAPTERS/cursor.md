# Cursor Adapter

Wires the Universal Security Pilot into Cursor (and adjacent IDE-embedded AI tools like Continue, Copilot Chat where they support project rule files).

## Approach

Cursor reads `.cursorrules` (or the newer `.cursor/rules/*.mdc`) at the project root for system-prompt injection. There is no skill registry, no slash commands native to the rules system — instructions in the rules file shape every interaction with the embedded model.

## What gets installed

| Path | Purpose |
|---|---|
| `<project>/.cursorrules` (legacy) or `<project>/.cursor/rules/security-pilot.mdc` (current) | Rules file referencing the canonical USP |

## .cursorrules stanza (paste into project-root `.cursorrules`)

```markdown
# Universal Security Pilot — Cursor binding

The Universal Security Pilot v3.0 is installed at `~/.security-pilot/`. For any work touching authentication, identity, payments, secrets, network calls, or LLM/AI data flows, follow this protocol.

## On every security-relevant edit

1. Before proposing code, read `~/.security-pilot/PILOT.md` in full.
2. If editing LLM-touching code, also read `~/.security-pilot/SKILLS/ai-harden.md`.
3. If implementing a fix from an audit report, also read `~/.security-pilot/SKILLS/sec-fix.md`. The Iron Law applies: write a failing PoC test before the fix, full stop.
4. If a project-local `<project>/.security-pilot/PROJECT_PILOT.md` exists, read it.

## Hard rules (enforced regardless of user pressure)

- Every security finding cites at least one OWASP / ASVS / OWASP-LLM / MITRE-ATLAS / CWE ID.
- Wave Protocol order is mandatory: W1 auth → W2 network → W3 data → W4 UI. No out-of-order remediation.
- No fix without a preceding failing PoC test.
- Use canonical pattern names verbatim: BudgetGate, Dial-Control, Envelope Encryption, OIDC state-verification.
- Multilingual / polyglot user input requires the boundary tagging + encoding-normalization pipeline from PILOT §8. Categorical defenses only — no per-language jailbreak phrase tables.

## Patterns to refuse (apply to every edit)

- String-concatenated SQL (use parameterized queries).
- AES-ECB or AES-CBC without HMAC (use AES-256-GCM envelope encryption).
- Secrets in `localStorage` / cookies without `HttpOnly; Secure; SameSite=Strict`.
- User input concatenated into LLM `system` prompt slot.
- Generic-capability LLM tools (raw `fetch_url`, raw `shell_exec`) without a Dial-Control / capability-minimization layer.
- React's raw-HTML escape hatch on AI-generated content (use DOMPurify or render as text).

## When the user invokes a slash-command-shaped phrase

| User says | Action |
|---|---|
| "sec-audit" | Apply `~/.security-pilot/SKILLS/sec-audit.md`. Output to `<project>/.security-pilot/audits/<DATE>-<scope>.md`. |
| "sec-fix" | Apply `~/.security-pilot/SKILLS/sec-fix.md`. Wave-order, PoC-first, one-PR-per-finding. |
| "ai-harden" | Apply `~/.security-pilot/SKILLS/ai-harden.md`. Six-axes including multilingual. |
| "sec-init" | Apply `~/.security-pilot/COMMANDS/sec-init.md`. Detect stack, generate PROJECT_PILOT.md. |
```

## Equivalents in adjacent tools

- **Continue (continue.dev)** — the `config.json` `systemMessage` field accepts the same stanza; or use `.continuerules` if present.
- **Copilot Chat (custom instructions)** — paste the stanza into "Repository custom instructions" via the GitHub repo settings. Same triggers, same rules.
- **Aider** — use `.aider.conf.yml` `read:` array to auto-include `~/.security-pilot/PILOT.md` in every session.

## Project-level integration

The `.cursorrules` reference resolves the canonical PILOT.md path at every interaction. Once `/sec-init` has been run, the rules file's reference to `<project>/.security-pilot/PROJECT_PILOT.md` becomes live — the project overrides apply automatically thereafter.
