#!/usr/bin/env bash
# usp-redact-secrets.sh — beforeReadFile hook. Denies the read when the file
# content matches one of the credential prefix patterns from
# COMMANDS/sec-init.md Step 4 (Pre-Audit Sanity Check).
#
# Patterns covered:
#   AKIA / ASIA — AWS access keys
#   AIza        — Google API
#   ghp_ / gho_ / ghs_ — GitHub tokens
#   xox[abps]-  — Slack
#   sk_live_ / sk_test_ — Stripe
#   eyJ...      — JWT shape (header.payload.signature)
#   -----BEGIN ... PRIVATE KEY----- — PEM private keys
#
# Requires: jq.

input="$(cat)"

content="$(printf '%s' "$input" | jq -r '.content // empty' 2>/dev/null || true)"
file_path="$(printf '%s' "$input" | jq -r '.file_path // empty' 2>/dev/null || true)"

patterns='(AKIA|ASIA)[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{35}|gh[pos]_[A-Za-z0-9]{36}|xox[abps]-[A-Za-z0-9-]+|sk_(live|test)_[A-Za-z0-9]+|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'

if printf '%s' "$content" | grep -qE "$patterns" 2>/dev/null; then
  cat <<__DENY__
{"permission":"deny","userMessage":"USP: file '${file_path}' contains a probable credential. Treat as compromised — see ~/.security-pilot/COMMANDS/sec-init.md Step 4 for rotation guidance."}
__DENY__
  exit 3
fi

cat <<'__ALLOW__'
{"permission":"allow"}
__ALLOW__
