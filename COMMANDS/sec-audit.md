# /sec-audit — Command Logic

## Purpose
Run a merciless zero-trust security audit against the current project, branch, file, or specified scope, producing a Markdown report mapped to OWASP/ASVS/LLM/ATLAS/CWE.

## Arguments
- `<scope>` (optional) — file path, directory path, or the literal token `branch`. If empty, audit the current git branch's diff against the default branch.

## Logic (agent must follow this sequence)

1. **Load reference material.**
   Read `~/.security-pilot/PILOT.md` and `~/.security-pilot/SKILLS/sec-audit.md` in full. If a project-local `<project>/.security-pilot/PROJECT_PILOT.md` exists, read it as well — it contains stack-specific footguns and allowlists. The canonical PILOT.md takes precedence on any conflict.

2. **Resolve scope.**
   - If `<scope>` is a path: that path.
   - If `<scope>` is `branch`: full diff between current branch and default branch (`main`/`master`).
   - If `<scope>` is empty: same as `branch`.

3. **Run the audit per `SKILLS/sec-audit.md`.**
   Walk the eight rules from PILOT.md. Produce the structured report using the template defined in the skill.

4. **Resolve output path.**
   ```
   project_root = git rev-parse --show-toplevel || directory of detected manifest

   if exists($project_root/.security-pilot/audits/):
       output = $project_root/.security-pilot/audits/<DATE>-<scope-slug>.md
   elif project_root identifiable:
       create $project_root/.security-pilot/audits/
       output = $project_root/.security-pilot/audits/<DATE>-<scope-slug>.md
   else:
       output = ~/.security-pilot/audits/<DATE>-<scope-slug>.md
   ```

5. **Write the report and report back.**
   Print the path, the finding count by severity, and the Wave distribution.
