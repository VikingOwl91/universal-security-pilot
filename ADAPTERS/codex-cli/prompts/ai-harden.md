# ai-harden

You are executing the Universal Security Pilot's `/ai-harden` command — audit and harden LLM/AI data flows against OWASP LLM Top 10, MITRE ATLAS, and multilingual / polyglot adversarial input.

Read these files in full before any hardening work:

1. `~/.security-pilot/PILOT.md`
2. `~/.security-pilot/SKILLS/ai-harden.md`
3. `~/.security-pilot/COMMANDS/ai-harden.md`

If `<project>/.security-pilot/PROJECT_PILOT.md` exists, also read it.

## Hardening scope

`$ARGUMENTS`

Scope resolution:

- If a path was supplied, use it.
- Otherwise, scan the project for LLM-integration markers:
  - Imports of `anthropic`, `openai`, `cohere`, `mistralai`, `langchain`, `llamaindex`, `vertexai`, `bedrock`.
  - Calls to `messages.create`, `chat.completions.create`, `generate_content`.
  - Strings like `system_prompt`, `system:`, `system_instruction`.
  - Tool / function-calling schemas.
  - RAG indicators: vector DB clients, embedding calls.
- Produce the file list as the audit scope.

## Procedure

Follow `COMMANDS/ai-harden.md` exactly:

- Run the six-axes assessment from `SKILLS/ai-harden.md`. Axes 1–5 always; axis 6 (multilingual / polyglot) when the input surface accepts free-form natural language.
- Use the canonical pattern names verbatim: BudgetGate, Dial-Control, Envelope Encryption.
- Resolve the output path the same way as `/prompts:sec-audit` — write to `<project>/.security-pilot/audits/<DATE>-ai-harden-<slug>.md`, or fall back to `~/.security-pilot/audits/` when no project root.

Report back: findings per axis, OWASP LLM and MITRE ATLAS coverage, indirect-injection vectors found, multilingual checklist status.
