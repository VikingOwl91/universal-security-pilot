# /ai-harden — Command Logic

## Purpose
Audit and harden LLM/AI data flows against OWASP LLM Top 10 and MITRE ATLAS threats, including multilingual / polyglot adversarial input.

## Arguments
- `<scope>` (optional) — file or directory containing LLM-touching code. If empty, scan the project for LLM-integration markers.

## Logic (agent must follow this sequence)

1. **Load reference material.**
   Read `~/.security-pilot/PILOT.md` and `~/.security-pilot/SKILLS/ai-harden.md` in full. If `<project>/.security-pilot/PROJECT_PILOT.md` exists, read it.

2. **Resolve scope.**
   - If `<scope>` is supplied, use it.
   - Otherwise, scan the project for LLM-integration markers:
     - Imports of `anthropic`, `openai`, `cohere`, `mistralai`, `langchain`, `llamaindex`, `vertexai`, `bedrock`
     - Calls to `messages.create`, `chat.completions.create`, `generate_content`
     - Strings like `system_prompt`, `system:`, `system_instruction`
     - Tool/function-calling schemas
     - RAG indicators: vector DB clients, embedding calls
   - Produce the file list as the audit scope.

3. **Run the six-axes assessment per `SKILLS/ai-harden.md`.**
   Axes 1–5 always; axis 6 (multilingual / polyglot) when the input surface accepts free-form natural language. Use the canonical pattern names verbatim (BudgetGate, Dial-Control, Envelope Encryption).

4. **Resolve output path.**
   Same resolution as `/sec-audit` — write to `<project>/.security-pilot/audits/<DATE>-ai-harden-<slug>.md` or fallback to `~/.security-pilot/audits/`.

5. **Report back.**
   Findings per axis, OWASP LLM and ATLAS coverage, indirect-injection vectors found, multilingual checklist status.
