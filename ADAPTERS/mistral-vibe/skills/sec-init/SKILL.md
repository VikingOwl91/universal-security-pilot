---
name: sec-init
description: Onboard the current project to the Universal Security Pilot. Detects the tech stack, runs an immediate-exposure secret scan, and generates a project-local PROJECT_PILOT.md plus the audits directory. Run once per project. Invoke as `/sec-init`.
user-invocable: true
---

# sec-init — Universal Security Pilot

Onboard the current project to the canonical Universal Security Pilot v3.0. The skill body below is a thin wrapper: read the canonical files in full and follow them exactly.

## Required reads (load before any onboarding work)

1. `~/.security-pilot/PILOT.md`
2. `~/.security-pilot/COMMANDS/sec-init.md`

If `<project>/.security-pilot/PROJECT_PILOT.md` already exists, read it too so you can ask the user whether to skip, refresh, or overwrite — never silently clobber existing project pilots.

## Procedure

Execute `COMMANDS/sec-init.md` exactly. The headline steps:

1. Detect the tech stack from manifest files.
2. **Immediate-exposure secret scan** — both passes (git-tracked sensitive filenames, then content-pattern scan). This is a blocker, not optional. Any hit MUST lead the report-back with the CRITICAL BLOCKER advisory before anything else.
3. Generate `<project>/.security-pilot/PROJECT_PILOT.md` with stack-specific footgun rows, empty Dial-Control / CORS / OIDC / LLM allowlists for the user to fill, and a project-constraints section.
4. Create `<project>/.security-pilot/audits/` with `.gitkeep` and a `.gitignore` rule that keeps audit reports out of git by default.

## Hard rules

- Step 2 (immediate-exposure scan) is mandatory and must block all other output if it finds anything.
- Never silently overwrite an existing `PROJECT_PILOT.md`.
- Never modify `.gitignore` without confirmation.
- Leave allowlists empty — do not invent values for the user.
