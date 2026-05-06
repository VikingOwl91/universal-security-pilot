---
name: ai-harden
description: Audit and harden LLM/AI data flows against OWASP LLM Top 10, MITRE ATLAS, and multilingual / polyglot adversarial input. Six-axes assessment including prompt injection, system-prompt leakage, insecure output handling, BudgetGate, tool-exposure SSRF, and polyglot adversarial input. Invoke as `$ai-harden [scope]`.
---

# ai-harden — Universal Security Pilot

Audit and harden LLM/AI surfaces driven by the canonical Universal Security Pilot v3.0 skill. The skill body below is a thin wrapper: read the canonical files in full and follow them exactly.

## Required reads (load before any hardening work)

1. `~/.security-pilot/PILOT.md`
2. `~/.security-pilot/SKILLS/ai-harden.md`
3. `~/.security-pilot/COMMANDS/ai-harden.md`

If `<project>/.security-pilot/PROJECT_PILOT.md` exists, also read it.

## Scope

The user invokes this skill with `$ai-harden [scope]`:

- Path argument → use that file or directory.
- No argument → scan the project for LLM-integration markers: imports of `anthropic`, `openai`, `cohere`, `mistralai`, `langchain`, `llamaindex`, `vertexai`, `bedrock`; calls to `messages.create`, `chat.completions.create`, `generate_content`; strings like `system_prompt` / `system:` / `system_instruction`; tool/function-calling schemas; RAG indicators (vector DB clients, embedding calls).

## Procedure

Follow `COMMANDS/ai-harden.md` exactly:

- Run the six-axes assessment from `SKILLS/ai-harden.md`. Axes 1–5 always; axis 6 (multilingual / polyglot) when the input surface accepts free-form natural language.
- Use the canonical pattern names verbatim: BudgetGate, Dial-Control, Envelope Encryption.
- Resolve the output path the same way as `$sec-audit` — write to `<project>/.security-pilot/audits/<DATE>-ai-harden-<slug>.md`, or fall back to `~/.security-pilot/audits/`.

Report back: findings per axis, OWASP LLM and MITRE ATLAS coverage, indirect-injection vectors found, multilingual checklist status.
