# sec-init

You are executing the Universal Security Pilot's `/sec-init` command — onboard the current project to USP.

Read these files in full before doing anything else:

1. `~/.security-pilot/PILOT.md`
2. `~/.security-pilot/COMMANDS/sec-init.md`

If `<project>/.security-pilot/PROJECT_PILOT.md` already exists, read it as well so you can ask the user whether to skip, refresh, or overwrite.

Then execute the procedure defined in `COMMANDS/sec-init.md` exactly.

## Hard rules

- Step 4 (Pre-Audit Sanity Check — Immediate-Exposure Scan) is a blocker, not an optional scan. Run both passes (git-tracked sensitive files by name, then content-pattern scan on git-tracked files). If any match, the report-back MUST lead with the CRITICAL BLOCKER advisory before any other section.
- Never silently overwrite an existing `PROJECT_PILOT.md`.
- Never modify `.gitignore` without confirmation.
- Leave allowlists empty for the user to fill — do not invent values.
