# /sec-init — Command Logic

## Purpose
Onboard a project to the Universal Security Pilot. Detects the tech stack, generates a project-local `PROJECT_PILOT.md` that inherits from the canonical PILOT.md and adds stack-specific footguns and allowlists, and creates the audits directory.

## Arguments
None. Acts on the current working directory's project root (resolved via `git rev-parse --show-toplevel` or the nearest manifest).

## Logic (agent must follow this sequence)

1. **Resolve project root.**
   ```
   project_root = git rev-parse --show-toplevel
   ```
   If not in a git repo, fall back to the directory of the nearest manifest file searching upward (max 5 levels). If still nothing, abort and tell the user to run from inside a project.

2. **Idempotency check.**
   If `$project_root/.security-pilot/PROJECT_PILOT.md` already exists, ask the user whether to (a) skip, (b) refresh stack detection only, or (c) overwrite. Do not silently overwrite.

3. **Detect tech stack.**
   Glob the project root for the markers below. Aggregate matches into a stack profile.

   | Manifest | Stack signal |
   |---|---|
   | `package.json` | Node / JS / TS — inspect `dependencies` for `react`/`vue`/`svelte`/`next`/`express`/`fastify`/`@anthropic-ai/sdk`/`openai`/etc. |
   | `Cargo.toml` | Rust — inspect for `actix-web`/`axum`/`rocket`/`tokio`/etc. |
   | `go.mod` | Go — inspect for `gin`/`echo`/`fiber`/`chi`/etc. |
   | `pyproject.toml` / `requirements.txt` / `Pipfile` | Python — inspect for `fastapi`/`flask`/`django`/`anthropic`/`openai` |
   | `pom.xml` / `build.gradle` / `build.gradle.kts` | Java / Kotlin — inspect for Spring, Quarkus, Micronaut |
   | `composer.json` | PHP — Laravel / Symfony |
   | `Gemfile` | Ruby — Rails / Sinatra |
   | `*.csproj` / `*.sln` | C# / .NET |
   | `mix.exs` | Elixir / Phoenix |
   | `Dockerfile` | Containerized — flag image hygiene as in-scope |
   | `*.tf` / `*.tfvars` | Terraform — IaC scope |
   | `Chart.yaml` / `values.yaml` | Helm / Kubernetes |

4. **Pre-Audit Sanity Check — Immediate-Exposure Scan.**

   Before any directory is created or any audit is queued, scan **git-tracked** files for high-risk artifacts that constitute immediate compromise if the repo is even briefly visible. This is a blocker, not a finding — the threat exists *now*, not after a review pass.

   ### Scan procedure

   Run two passes:

   **Pass 1 — git-tracked sensitive files (highest priority):**
   ```bash
   git ls-files | grep -E '(^|/)(\.env(\.[a-z]+)?$|.*\.(db|sqlite|sqlite3|pem|key|p12|pfx|jks|asc|gpg)$|id_rsa|id_dsa|id_ecdsa|id_ed25519|.*\.kube/config|credentials\.json|service-account.*\.json)'
   ```

   **Pass 2 — content-pattern scan on git-tracked files (secrets that don't match a filename):**
   - Look for the literal patterns of common credential prefixes in committed files: `AKIA`/`ASIA` (AWS access keys), `AIza` (Google API), `ghp_`/`gho_`/`ghs_` (GitHub tokens), `xox[ab]-` (Slack), `sk_live_`/`sk_test_` (Stripe), `eyJ` followed by base64 with a JWT shape, `-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----`.
   - Scan only the working-tree contents of git-tracked files; do not scan history (out of scope for `/sec-init`; the user's existing tooling — `gitleaks`, `trufflehog`, BFG — handles history).
   - Limit to ≤200 files scanned for content; if more, sample and report partial coverage.

   ### Severity and surfacing

   Every match from either pass is recorded as:

   ```
   [CRITICAL BLOCKER: IMMEDIATE EXPOSURE]
   File: <path>
   Reason: <one of: "tracked sensitive file by name" | "credential prefix detected in tracked file content">
   Detected pattern: <filename glob match | content-prefix>
   Status: ACTIVE — assume compromised; rotate before remediation
   ```

   ### Required user advisory

   Whenever **at least one** Immediate Exposure is found, the `/sec-init` output must lead with this advisory before any other section:

   > ⚠️ **CRITICAL BLOCKER — IMMEDIATE EXPOSURE**
   >
   > Sensitive artifacts are currently tracked in this repository. Treat each as compromised:
   >
   > 1. **Untrack** the file: `git rm --cached <path>` (do NOT just delete from disk — git history retains it).
   > 2. **Add** the corresponding pattern to `.gitignore`.
   > 3. **Rotate** the credential — a new database password, a fresh API key, regenerated SSH/PGP keys, a re-issued certificate. Assume the old value is in attacker hands the moment it left the laptop.
   > 4. **Purge from history** if the file was ever pushed: `git filter-repo --path <path> --invert-paths` (or BFG); coordinate with all collaborators because hashes will rewrite.
   > 5. **Re-run** `/sec-init` once the working tree is clean.
   >
   > **`/sec-audit` should not be run until these blockers are resolved** — the audit's recommendations will be downstream of an already-leaked state.

   ### Behavior of `/sec-init` when blockers are present

   - Continue the rest of `/sec-init` (stack detection, `PROJECT_PILOT.md` generation, directory creation) — the user still needs the scaffold.
   - Embed the Immediate Exposure list at the **top** of the generated `PROJECT_PILOT.md` under a `## Pre-Audit Blockers` section.
   - The terminal report-back leads with the advisory above.

   ### When no blockers are found

   Record one line in the report-back: `Pre-Audit Sanity Check: clean (N files scanned by name, M by content)` and proceed normally.

5. **Create directory structure.**
   ```
   $project_root/.security-pilot/
     PROJECT_PILOT.md
     audits/         (empty placeholder, with .gitkeep if appropriate)
   ```

6. **Write `PROJECT_PILOT.md` from this template:**

   ```markdown
   ---
   title: Project Security Pilot
   parent: Universal Security Pilot v3.0 (~/.security-pilot/PILOT.md)
   project: <PROJECT_NAME>
   stack: <DETECTED STACK SUMMARY>
   generated: <YYYY-MM-DD>
   ---

   # Project Security Pilot — <PROJECT_NAME>

   This file inherits from the canonical pilot at `~/.security-pilot/PILOT.md`. **It cannot loosen any rule** in the canonical — only tighten or add project-specific guidance. On any conflict, the canonical wins.

   ## Pre-Audit Blockers

   <If Step 4 of /sec-init found Immediate Exposures, list each here under [CRITICAL BLOCKER: IMMEDIATE EXPOSURE] with file path, detection reason, and required action. If the working tree is clean, write a single line: "Pre-Audit Sanity Check: clean as of <YYYY-MM-DD>". /sec-audit must NOT be run until this section is empty / clean.>

   ## Detected Stack

   <bullet list of detected components: backend framework(s), frontend framework(s), DB, cache, queue, IaC, deployment target, LLM SDK if any>

   ## Stack-Specific Footguns

   <Lifted from PILOT.md §2 Context-Aware Safety table for each detected language. Include the relevant rows verbatim plus framework-specific items, e.g.:>

   - **<Language>** — <pilot row>
   - **<Framework>** — <framework-specific recurring footgun, e.g.: "Express: default body parser limit; trust-proxy off by default; cookie-parser without signed cookies">

   ## Project Allowlists (fill before first /ai-harden)

   - **HTTP egress allowlist** (used by Dial-Control): `[]`
   - **CORS allowed origins**: `[]`
   - **OIDC trusted issuers**: `[]`
   - **LLM-tool URL allowlist** (if any): `[]`

   ## Project-Specific Constraints

   <e.g.: "All money operations must go through Postgres `SELECT ... FOR UPDATE` or atomic UPDATE — see PILOT.md §4. Test under `go test -race`.">

   <Empty subsections to fill:>
   - Authentication scheme: …
   - Session storage: …
   - Secret management: …
   - Compliance regime (GDPR / HIPAA / PCI-DSS / etc.): …
   - Multilingual user surface (yes / no; if yes, supported languages): …

   ## Audit Output

   `.security-pilot/audits/<YYYY-MM-DD>-<scope>.md`

   ## Re-running /sec-init

   Stack changes? Re-run `/sec-init` and choose "refresh stack detection only" — preserves the allowlists and constraints sections.
   ```

7. **Append `.security-pilot/audits/` to `.gitignore` if appropriate.**
   Ask the user before modifying `.gitignore`. Default suggestion: ignore `audits/*.md` but keep the directory tracked via `.gitkeep` (audits often contain sensitive details and shouldn't be committed by default).

8. **Report back.**
   - **If Step 4 found Immediate Exposures, the report MUST lead with the CRITICAL BLOCKER advisory** (see step 4). Nothing else is more important.
   - Detected stack summary.
   - Path to the new `PROJECT_PILOT.md`.
   - Pre-Audit Sanity Check result line (clean, or count of blockers).
   - Suggested next step: if blockers exist → resolve them per the advisory; if clean → fill in the empty allowlist/constraints sections, then run `/sec-audit`.

## Anti-patterns

- Silently overwriting an existing `PROJECT_PILOT.md`.
- Modifying `.gitignore` without confirmation.
- Detecting a stack and then ignoring it (no footgun rows generated).
- Generating allowlists from imagination — always leave them empty for the user to fill.
- Creating `PROJECT_PILOT.md` outside `.security-pilot/` (e.g., at project root) — that is project-essentials territory.
