#!/usr/bin/env bash
# usp-mcp-dial-control.sh — beforeMCPExecution hook. Enforces the Dial-Control
# HTTP egress allowlist defined in <project>/.security-pilot/PROJECT_PILOT.md.
#
# Progressive enforcement (matches the natural USP onboarding):
#   No project root, no PROJECT_PILOT.md, or empty allowlist → allow
#       (educational mode — usp-audit.sh still records the call).
#   Populated allowlist + URL substring match                → allow.
#   Populated allowlist + URL substring miss                 → ask.
#   No URL-shaped argument in the MCP payload                → allow
#       (not an HTTP-egress call by our heuristic).
#
# Allowlist source: the line in PROJECT_PILOT.md shaped like
#       - **HTTP egress allowlist** (used by Dial-Control): `[a, b, c]`
# Values are extracted from the first `[...]` block on that line, comma-split,
# whitespace and quotes trimmed. Substring match (so "api.example.com" allows
# "https://api.example.com/v1/foo").
#
# Requires: jq.

input="$(cat)"

allow() { cat <<'__OK__'
{"continue":true,"permission":"allow"}
__OK__
  exit 0
}

ask() { cat <<__ASK__
{"continue":true,"permission":"ask","userMessage":"USP Dial-Control: $1","agentMessage":"Universal Security Pilot's Dial-Control flagged an MCP call to '$2' — '$2' is not in the project's HTTP egress allowlist (<project>/.security-pilot/PROJECT_PILOT.md). Confirm the egress is intended, or extend the allowlist."}
__ASK__
  exit 0
}

project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$project_root" ]] || allow

pilot="$project_root/.security-pilot/PROJECT_PILOT.md"
[[ -f "$pilot" ]] || allow

allowlist_raw="$(grep -E '^\s*-\s+\*\*HTTP egress allowlist\*\*' "$pilot" 2>/dev/null \
  | head -n1 \
  | sed -E 's/.*\[([^]]*)\].*/\1/' \
  | tr -d ' "`'"'")"

[[ -n "$allowlist_raw" ]] || allow

url="$(printf '%s' "$input" | jq -r '
  .arguments.url // .arguments.uri // .arguments.endpoint // .arguments.host //
  .params.url    // .params.uri    // .params.endpoint    // .params.host    //
  empty' 2>/dev/null || true)"

[[ -n "$url" ]] || allow

IFS=',' read -ra entries <<< "$allowlist_raw"
for entry in "${entries[@]}"; do
  [[ -z "$entry" ]] && continue
  if [[ "$url" == *"$entry"* ]]; then
    allow
  fi
done

ask "MCP egress to '$url' is not in the project's HTTP egress allowlist." "$url"
