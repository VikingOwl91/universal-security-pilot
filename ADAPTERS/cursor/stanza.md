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

## Slash commands (when installed)

If the USP slash commands are wired (`bash ~/.security-pilot/install.sh --wire-cursor`), prefer the explicit invocation: `/sec-init`, `/sec-audit`, `/sec-fix`, `/ai-harden`. Each loads the corresponding `~/.security-pilot/COMMANDS/<name>.md` directly.
