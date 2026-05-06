# sec-precommit — Wave 0: Pre-Commit Gating (Shift-Left)

> **STATUS: v3.1-alpha WORKING DRAFT.** Citation map, footgun catalogue, PoC-test recipes, and bypass-resistance checklist are in place. The skill is **not yet GA** — recipes have not been validated end-to-end on a reference project, and one or two row IDs still need primary-source citation review. Do not invoke against production audits until the canonical pilot is cut from `3.1.0-alpha` to a non-alpha `3.1`.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 0 is the **Shift-Left entry point** of the framework. It runs *before* the agent can call `git commit` on an artifact that W1–W4 would later have to audit. A committed secret cannot be audited out — it has to never reach the commit. W0 enforces that gate at the local hook layer, *and* at the CI / branch-protection layer that catches `--no-verify` bypasses.

Successful W0 enforcement is a **prerequisite** for W1. If a pre-commit gate would have blocked a finding, the gate is the fix; the audit row for the finding reduces to "ensure the gate is configured and unbypassable in normal flow."

## What this skill produces

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-precommit.md` with:

- The W0 audit report header (date, branch, scope, threat model: who can push, who can bypass).
- Per-finding rows using the template at the bottom of this file.
- A Wave-0 remediation order (blast-radius descending: server-side bypass > committed secret in current HEAD > hook gap > history hygiene).
- A "tests to write first" list — every W0 fix ships with a failing PoC test per the Iron Law.

## When to use

- "Audit our pre-commit hooks."
- Any onboarding to a project that does not run `/sec-init`-equivalent.
- Before promoting a repo from internal to public.
- After any incident involving a committed secret, even if rotated — the gate is the lesson.
- As a prerequisite of `/sec-audit` on a repo with no documented W0 posture.

## When NOT to use

- A single-PR review where W0 has already been audited recently and nothing about the hook stack has changed.
- A repo where artifact production happens entirely outside git (e.g., direct registry push from CI without a source repo).
- IDE-only inline linting questions — that is a different layer.

## Pre-audit grounding

1. **Inventory the hook framework.** `pre-commit`, `husky`, `lefthook`, native `.git/hooks/`, or none. Mixed installs are a finding by themselves (one will silently shadow the other).
2. **Read the `.pre-commit-config.yaml` / `lefthook.yml` / `.husky/` directory.** Note pinned versions, hook IDs, and any conditional skips (`always_run: false`, `stages: [commit]` with no `pre-push`).
3. **Walk git history with the secret-scan you intend to recommend.** Pre-existing committed secrets are out-of-scope for *gating* but in-scope for *remediation order* — they have to be invalidated and rotated before the gate is meaningful.
4. **Check CI for hook re-execution.** Local hooks alone are not enforcement. The CI must re-run the same hooks against the pushed ref, or the protection is local-only and defeated by `--no-verify`.
5. **Confirm Pre-Audit Sanity Check is clean.** If the project's `PROJECT_PILOT.md` lists `[CRITICAL BLOCKER: IMMEDIATE EXPOSURE]` items, abort the audit and surface the blockers per `/sec-init`. W0 cannot meaningfully audit a repo whose secrets have already shipped.

## Citation Map — OWASP / ASVS / CWE

Every W0 finding row maps to at least one ID from this table. "Best practice" is not a citation.

| Category | OWASP Top 10 (2021) | OWASP ASVS L2 | CWE |
|---|---|---|---|
| Hardcoded / committed credentials | A07 Identification & Authentication Failures · A02 Cryptographic Failures | V14.1.5 (no inline secrets in build configs) · V2.10.4 (no inline secrets in source) · V8.3.4 (sensitive data not logged) | CWE-798 Use of Hardcoded Credentials · CWE-540 Inclusion of Sensitive Information in Source Code · CWE-200 Information Disclosure |
| Insecure build / artifact configuration | A05 Security Misconfiguration | V14.1.1 (defined build process) · V14.2.1 (dependencies pinned) · V14.3.2 (hardening defaults) | CWE-732 Incorrect Permission Assignment · CWE-1357 Reliance on Insufficiently Trustworthy Component · CWE-250 Execution with Unnecessary Privileges |
| Bypass / enforcement gaps | A05 Security Misconfiguration · A04 Insecure Design | V1.1.4 (security verified at every change) · V14.2.4 (build-pipeline integrity) | CWE-693 Protection Mechanism Failure · CWE-807 Reliance on Untrusted Inputs in a Security Decision · CWE-1059 Insufficient Technical Documentation |

Standard citation line in a W0 finding:
```
**Maps to:** OWASP A07 · ASVS V14.1.5 · CWE-798 · W0-3
```

## Footgun Catalogue — Wave 0

Each row uses the framework-footguns block format: **Maps to · Symptom · Why wrong · Canonical fix · PoC test shape.**

### Category P0 — Committed Secrets (the primary mission)

#### W0-1 — `.env` / `.env.local` file committed to git
**Severity:** Critical  *(direct credential exposure, no preconditions)*
**Maps to:** OWASP A07 · ASVS V14.1.5 · CWE-798 · CWE-540
**Symptom in code:** Any `.env*` file (other than documented examples like `.env.example`) tracked by git, or appearing in a `git log -- .env*` history.
**Why it's wrong:** Real-world impact — Toyota Motor Corporation (Dec 2022) disclosed that an access key for ~296,000 customer records was leaked because a partner committed an `.env`-equivalent file to a public GitHub repo. The exposure window was nearly five years before discovery. `.env` files routinely contain `DATABASE_URL`, OAuth client secrets, and signing keys — all of which are valid until rotated, regardless of whether the file is later removed (git history preserves blobs).
**Canonical fix:** (a) `.gitignore` lists every `.env*` pattern except documented examples; (b) pre-commit hook (gitleaks / trufflehog / custom regex) blocks the commit; (c) CI re-runs the same scan on the pushed diff against the merge-base, not just `HEAD~1`; (d) for any pre-existing committed secret, the secret is **rotated first** and *then* removed from history with `git filter-repo` — order matters because removing-then-rotating leaks the rotation window.
**PoC test shape:** `Test: a commit that adds .env containing AKIA[A-Z0-9]{16} is rejected by the pre-commit hook with a non-zero exit and a structured error pointing at the matching line.`

#### W0-2 — Next.js `NEXT_PUBLIC_*` variable carrying a secret
**Severity:** Critical  *(secret inlined into every client bundle, no preconditions)*
**Maps to:** OWASP A02 · ASVS V14.3.2 · CWE-540 · CWE-200
**Symptom in code:** A `.env.production`, `next.config.js`, or `vercel.json` setting a `NEXT_PUBLIC_<NAME>` value whose name or content suggests a secret (`NEXT_PUBLIC_API_KEY`, `NEXT_PUBLIC_STRIPE_SECRET`, `NEXT_PUBLIC_DATABASE_URL`).
**Why it's wrong:** Anything with the `NEXT_PUBLIC_` prefix is **inlined into the client bundle at build time** — Next.js documents this explicitly. The variable ships to every browser that loads the app, with full source-map fidelity. The `_PUBLIC_` infix lulls reviewers into thinking the value was *intended* to be public; the variable name (`API_KEY`, `STRIPE_SECRET`) shows it wasn't. GitGuardian's annual State of Secrets Sprawl reports (2022, 2023, 2024) consistently flag `NEXT_PUBLIC_*`-prefixed leaks as a top-10 misconfig pattern in scanned public repos.
**Canonical fix:** (a) Hook denies any commit adding `NEXT_PUBLIC_*` whose name matches a deny-list (`*KEY*`, `*SECRET*`, `*TOKEN*`, `*PASSWORD*`, `*DATABASE_URL*`, `*PRIVATE*`); (b) for variables that genuinely *must* ship to the client (e.g., a Stripe *publishable* key — `pk_live_...`), require an explicit `# allow: public-by-design <reason>` comment on the line, and the hook honors it only with the comment present; (c) build-time check that decompiled bundle does not contain server-side env values.
**PoC test shape:** `Test: a commit adding NEXT_PUBLIC_STRIPE_SECRET=sk_live_… is rejected; the same line with a documented "publishable key" comment and a pk_test_… value passes.`

#### W0-3 — Drizzle / Prisma / `drizzle-kit` config with hardcoded `DATABASE_URL`
**Severity:** Critical  *(elevated-privilege DB credential; write-side compromise on leak)*
**Maps to:** OWASP A07 · ASVS V14.1.5 · CWE-798
**Symptom in code:** `drizzle.config.ts`, `prisma/schema.prisma`, `knexfile.ts`, or equivalent containing a literal connection string with credentials (`postgres://user:pass@host/db`) instead of `process.env.DATABASE_URL`.
**Why it's wrong:** Migration tools are commonly run with elevated DB privileges (CREATE / DROP). A leaked migration-tool credential is a write-side compromise, not just a read-side one. The pattern recurs because dev-time examples in framework docs sometimes inline credentials for clarity, and devs copy-paste them. ORMs that auto-load `.env` (Drizzle, Prisma) make the inline form actively unnecessary, which makes it a stronger signal of either ignorance or carelessness.
**Canonical fix:** (a) Hook denies commits to migration-tool config files containing the pattern `://[^:]+:[^@]+@`; (b) config files reference `process.env.DATABASE_URL` only; (c) `.env.example` documents the variable name without a value; (d) for CI migrations, the secret comes from the secret store, not the repo.
**PoC test shape:** `Test: a drizzle.config.ts with url: "postgres://admin:hunter2@db.example.com/prod" is rejected; the same file with url: process.env.DATABASE_URL passes.`

#### W0-4 — Helm `values.yaml` with plaintext credentials committed
**Severity:** High  *(scoped to repo-access boundary; promote to Critical if repo is public)*
**Maps to:** OWASP A05 · A02 · ASVS V14.1.5 · V14.3.2 · CWE-798
**Symptom in code:** A `values.yaml`, `values-prod.yaml`, or chart-bundled `secrets.yaml` containing literal passwords, API tokens, or signing keys — *not* a templated reference to an external secret store.
**Why it's wrong:** Helm renders these into `Secret` manifests at install time. The plaintext sits in git, in the rendered manifest, in `helm get values`, and (depending on history retention) in every cluster snapshot. This is the W0 analogue of W6's runtime "no plaintext secrets in YAML" rule — caught one layer earlier. Mercedes-Benz (Jan 2024) disclosed a token leak that began with credential material committed to a private GitHub repo whose access scope drifted; the same defect would have been caught by a pre-commit Helm-values scan.
**Canonical fix:** (a) Pre-commit policy lint (`conftest test` against an OPA policy, or `helm template | gitleaks detect`) rejects any chart whose rendered output contains a secret-looking pattern; (b) charts reference `External Secrets Operator`, `Sealed Secrets`, `SOPS`, or a cloud-native CSI driver — never inline; (c) reviewer checklist requires `helm template <chart> | grep -E '(password|token|secret).*: [^$]'` to return empty before merge.
**PoC test shape:** `Test: a values-prod.yaml with database.password: "hunter2" is rejected by the chart-lint hook; the same file with database.password: "{{ .Values.dbPassword | required \"…\" }}" and a sealed-secret reference passes.`

#### W0-5 — AWS access key in test fixture / mock data
**Severity:** Critical  *(prefix-match scanners trip; typo-of-real-key is the failure mode)*
**Maps to:** OWASP A07 · ASVS V14.1.5 · V8.3.4 · CWE-798 · CWE-540
**Symptom in code:** Any `.json`, `.yaml`, `.fixture.ts`, or `__fixtures__/` file containing a literal `AKIA[0-9A-Z]{16}` (long-term root/user key) or `ASIA[0-9A-Z]{16}` (temporary STS credential), even if labeled "fake" or "test".
**Why it's wrong:** Two compounding problems. First, automated scanners (GitHub's secret-scanning, AWS's own scanner) match on the prefix and *will* flag the repo and quarantine the key — even if it was syntactically invalid, this triggers an alert storm and a false-positive disclosure. Second, devs sometimes **typo a real key** into a test fixture and don't notice; the prefix match is their only seatbelt. Uber's 2016 incident — 57M user records exposed — began with credentials committed to a private GitHub repo. The repo wasn't public; the access token to it was reused.
**Canonical fix:** (a) Hook rejects any file matching `(AKIA|ASIA)[0-9A-Z]{16}` regardless of context; (b) test fixtures use the documented AWS test-pattern values (`AKIAIOSFODNN7EXAMPLE`) or a clearly non-conforming placeholder (`AKIA-FAKE-FOR-TEST-ONLY`); (c) the hook's regex is *post-decode* — the file is checked after base64 / gzip / hex decoding, bounded to 3 passes per PILOT §8.
**PoC test shape:** `Test: a fixture file with awsAccessKeyId: "AKIA1234567890ABCDEF" is rejected; the same fixture using AKIAIOSFODNN7EXAMPLE passes.`

### Category P1 — Build-Artifact Configuration Drift

#### W0-6 — Dockerfile without `USER` directive (defaults to root)
**Severity:** Medium  *(defense-in-depth gap; blast-radius amplifier, not direct compromise)*
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-250 · CIS Docker Benchmark 4.1
**Symptom in code:** A `Dockerfile` whose final stage has no `USER <non-zero-uid>` directive before `CMD`/`ENTRYPOINT`.
**Why it's wrong:** Containers without `USER` run as UID 0. Combined with a kernel exploit, a missing `--read-only` mount, or a misconfigured `securityContext` at runtime, this expands the blast radius of every other defect by an order of magnitude. The runtime layer (W6) can constrain it via `runAsNonRoot: true`, but defense-in-depth says: catch at the source. NIST SP 800-190 §4.4 is unambiguous on this.
**Canonical fix:** (a) Pre-commit hook (`hadolint` rule `DL3002`) rejects Dockerfiles with no `USER` in the final stage; (b) the `USER` directive points to a numeric UID (not a name), so Kubernetes' `runAsNonRoot` admission can verify it without resolving `/etc/passwd` inside the image; (c) the base image is pinned by digest (see W0-7) so the user table can't drift under the same name.
**PoC test shape:** `Test: a Dockerfile with FROM node:20-alpine and no USER directive is rejected; the same file with USER 10001 in the final stage passes.`

#### W0-7 — Dockerfile `FROM` with mutable tag (no digest pin)
**Severity:** Medium  *(supply-chain risk; requires upstream tag mutation or compromise to exploit)*
**Maps to:** OWASP A05 · A06 Vulnerable & Outdated Components · ASVS V14.2.1 · CWE-1357
**Symptom in code:** `FROM <image>:<tag>` without a `@sha256:...` digest, especially `:latest`, `:alpine`, `:slim`, `:lts` style.
**Why it's wrong:** Tags are mutable refs. The same `node:20-alpine` you tested today can be a different blob tomorrow — sometimes via legitimate base-image updates, sometimes via supply-chain compromise. The Codecov bash uploader incident (CVE-2021-32638, April 2021) demonstrated the broader pattern: a build-time fetch resolved differently than the version reviewed, and exfiltrated CI environment secrets across thousands of downstream projects. Digest pinning closes the gap between "version reviewed" and "version built."
**Canonical fix:** (a) Hook (`hadolint` rule `DL3007` for `:latest`, plus a custom rule for any non-digest tag in production builds) rejects unpinned `FROM`; (b) base image is pinned by SHA256 digest in addition to a human-readable tag (`FROM node:20-alpine@sha256:...`); (c) Renovate / Dependabot is configured to PR digest updates so the pinning doesn't ossify into stale CVEs.
**PoC test shape:** `Test: a Dockerfile with FROM node:20-alpine is rejected; the same file with FROM node:20-alpine@sha256:<64hex> passes.`

#### W0-8 — Terraform output without `sensitive = true` on credential-bearing values
**Severity:** Medium  *(info disclosure scoped to CI-log readers; broadens the audience of the secret)*
**Maps to:** OWASP A09 Logging & Monitoring · A07 · ASVS V8.3.4 · CWE-200
**Symptom in code:** A `output "db_password"` (or `_token`, `_secret`, `_key`) block missing `sensitive = true`, allowing the value to render in `terraform plan` / `apply` output and in CI logs.
**Why it's wrong:** Terraform outputs are emitted to stdout during plan/apply, captured by CI logs, persisted for the configured retention window, and surfaced in PR comments by some integrations. A non-sensitive output of a generated DB password lands in CI logs that may be accessible to a wider engineering audience than the secret store itself. The fix is a single keyword; the omission is a one-line audit row.
**Canonical fix:** (a) Hook (`tflint` with `terraform_sensitive_variable` rule, or custom regex) rejects any output block whose name matches credential-keyword patterns and lacks `sensitive = true`; (b) variables that hold secrets are also marked `sensitive = true` so `terraform plan` doesn't echo them on diff; (c) CI logs are configured with a retention shorter than the secret rotation window.
**PoC test shape:** `Test: an output block named "db_admin_password" without sensitive = true is rejected by tflint; adding sensitive = true makes it pass.`

#### W0-9 — `package.json` postinstall script fetching arbitrary remote code
**Severity:** High  *(RCE-on-install if URL or DNS is compromised; full dev-environment scope)*
**Maps to:** OWASP A08 Software & Data Integrity Failures · ASVS V14.2.4 · CWE-829 · CWE-1357
**Symptom in code:** A `"postinstall": "curl <url> | sh"`, `"prepare": "node ./scripts/<remote-fetch>.js"`, or any lifecycle script in `package.json` that fetches and executes code from a non-pinned remote source at install time.
**Why it's wrong:** `npm install` runs lifecycle scripts with the developer's full shell environment, including any auth tokens, AWS credentials, or SSH keys in scope. An attacker who compromises the remote endpoint (or a typo'd domain) gets RCE-on-install across every consumer. The 2018 `event-stream` incident is the canonical example of a lifecycle-script-driven supply-chain compromise. Even when the URL is "trusted," the lack of integrity pinning makes the script behaviorally a moving target.
**Canonical fix:** (a) Hook rejects `package.json` lifecycle scripts containing `curl`/`wget`/`fetch` of remote URLs without an integrity check; (b) any required postinstall fetches resources via a vendored, lockfile-pinned dependency rather than ad-hoc shell; (c) `.npmrc` sets `ignore-scripts=true` for CI installs and explicitly enables scripts only for the workspace packages that need them.
**PoC test shape:** `Test: a package.json with "postinstall": "curl https://example.com/install.sh | sh" is rejected; a postinstall calling a workspace-local script via "node ./tools/setup.cjs" passes.`

### Category P2 — Hook Bypass and Enforcement Gaps

#### W0-10 — Pre-commit framework configured but `rev` floats
**Severity:** High  *(supply-chain on the gate itself; the gate is load-bearing)*
**Maps to:** OWASP A06 · A08 · ASVS V14.2.1 · V14.2.4 · CWE-1357
**Symptom in code:** `.pre-commit-config.yaml` with `rev: main`, `rev: master`, `rev: HEAD`, or any branch name (rather than a tag or commit SHA).
**Why it's wrong:** A floating `rev` means every dev's `pre-commit autoupdate` (or first-time `pre-commit install`) pulls a different version of the hook implementation. The hook itself becomes a moving target — and the hook is the gate that defends the repo. A compromised upstream (or a benign breaking change) silently flips the hook's behavior. Hook authors generally ship signed tags; not pinning to one is a self-inflicted supply-chain wound.
**Canonical fix:** (a) Every `repo:` entry in `.pre-commit-config.yaml` pins `rev:` to a tag (`v3.5.0`) or a 40-char commit SHA; (b) pre-commit version itself is pinned in CI (`pre-commit==<X.Y.Z>`); (c) Renovate/Dependabot updates the pin via PR so changes are reviewable, not silent.
**PoC test shape:** `Test: a .pre-commit-config.yaml with rev: main is rejected by the meta-hook; the same file with rev: v4.0.1 passes.`

#### W0-11 — Husky `prepare` script disabled when `CI=true`
**Severity:** High  *(disables enforcement at the layer that matters most; --no-verify ships freely)*
**Maps to:** OWASP A05 · A04 Insecure Design · ASVS V1.1.4 · V14.2.4 · CWE-693 · CWE-807
**Symptom in code:** A `package.json` with `"prepare": "is-ci || husky install"`, `"prepare": "husky install || true"`, or a Husky script that begins with `if [ "$CI" = "true" ]; then exit 0; fi`.
**Why it's wrong:** This pattern is widely copy-pasted from blog posts that justified it as a CI optimization ("husky is for dev environments, CI doesn't need git hooks"). The reasoning has the security model exactly backwards: **CI is the place that matters most**, because CI is where pushed branches arrive, and pushed branches may have been built locally with `git commit --no-verify`. Disabling the gate in CI means a `--no-verify` commit ships to the protected branch with zero re-validation. Local-only enforcement is theatre; the place that needs the strictest enforcement is exactly the place this pattern disables it.
**Canonical fix:** (a) CI re-runs the same hooks against the pushed ref (`pre-commit run --from-ref origin/main --to-ref HEAD` or equivalent), as a required check on the protected branch; (b) the `prepare` script does not short-circuit on `CI`; (c) branch protection rejects merges where the pre-commit CI job did not run; (d) the gate's enforcement level is documented in `PROJECT_PILOT.md` so future contributors don't "optimize" it back out.
**PoC test shape:** `Test: a feature-branch commit made with --no-verify (locally bypassing the gate) fails the CI pre-commit check on push and is blocked from merging by branch protection.`

#### W0-12 — Hooks installed only locally; CI does not re-run them
**Severity:** High  *(non-uniform enforcement across contributors; the hook is opt-in)*
**Maps to:** OWASP A05 · ASVS V14.2.4 · CWE-693 · CWE-1059
**Symptom in code:** Repo has `.pre-commit-config.yaml` or `.husky/`, but no corresponding CI job that runs the same hooks against the pushed ref. The README documents "we use pre-commit hooks" without saying "CI re-runs them."
**Why it's wrong:** This is the structural twin of W0-11, surfaced separately because it is independently common. A developer who clones the repo and never runs `pre-commit install` (or whose `.git/hooks/` is missing because the repo was clone-without-hooks-installed) commits without ever invoking the hook. The repo's "we use hooks" claim is only true for the subset of contributors who manually opted in. CI re-execution is the only mechanism that makes the gate uniform across contributors.
**Canonical fix:** (a) A CI workflow (`.github/workflows/pre-commit.yml` or equivalent) runs `pre-commit run --all-files` (full sweep) on `pull_request` and `pre-commit run --from-ref ${{ github.event.before }} --to-ref ${{ github.sha }}` (delta) on `push`; (b) the workflow is a required status check on protected branches; (c) the workflow uses the same pinned `rev:` / hook-implementation versions as local installs.
**PoC test shape:** `Test: a PR opened with a commit that adds .env containing AKIA[A-Z0-9]{16} fails the CI pre-commit job and the required-check gate prevents merge.`

#### W0-13 — Hook scanner runs only on the staged diff, never on the full file or history
**Severity:** Critical  *(load-bearing false sense of security; pre-existing leaks fully exposed)*
**Maps to:** OWASP A05 · A09 · ASVS V14.2.4 · V8.3.4 · CWE-693 · CWE-200
**Symptom in code:** A pre-commit hook configured with `pass_filenames: true` and a scanner invocation that reads only the staged diff (`gitleaks protect` instead of `gitleaks detect`, or a custom hook that calls `git diff --cached` only).
**Why it's wrong:** This is the **most insidious** W0 defect. The hook produces green output. The team believes they are protected. But every secret committed *before* the hook was installed remains in the repo's history, fully readable to anyone who can clone or who has historical access. New contributors clone the repo, get the secret in their working tree on first checkout, and the hook never fires (no addition, no diff). The hook's narrow scope creates a load-bearing false sense of security: the gate looks installed, the audit trail looks clean, the risk is unmitigated. This is the pattern most likely to be cited months later in a post-incident review as "we thought we had this covered."

**Real-world scenario (the silent killer in action):**

A developer at a 3-year-old startup asks their AI coding assistant: *"Set up secret scanning for our repo — we're about to open-source a sample app from the codebase."*

The assistant does what most AI coding agents do without the Pilot in scope: it picks the most popular tool (`gitleaks`), wires it into Husky, and chooses the documented pre-commit-friendly invocation:

```bash
$ npx husky add .husky/pre-commit "gitleaks protect --staged --redact --config .gitleaks.toml"
$ git add .husky/pre-commit .gitleaks.toml
$ git commit -m "feat: add secret scanning to pre-commit"
✔ no leaks found
[main 4f8c2d1] feat: add secret scanning to pre-commit
```

The agent reports: *"Secret scanning is configured. Any commit that adds a credential will be blocked at the hook stage. Verified by adding a test AKIA-prefixed key to a temp file — the hook caught it."* The dev runs a quick negative-case test: stages a fake key, commit fails, green tick. Ticket closed.

What neither the dev nor the agent looked at: 18 months earlier, a contractor committed a `.env.staging` file while debugging a deploy. Three weeks later, someone deleted the file in a cleanup PR. The production secret rotated 11 months after that — but only the *production* one. The *staging* `STRIPE_SECRET_KEY` from the deleted file is still live, still in `git log --all -- '.env*'`, still in commit `a3f2e9d` from May 2023. `gitleaks protect --staged` only inspects the working-tree-to-index delta. It never reads history. The hook the assistant installed has **zero coverage** of the actual leak.

A month after the open-source release, an external researcher runs `gitleaks detect` (the *full-history* mode) on the now-public repo. They find the staging key. They responsibly disclose. The post-mortem reads: *"We had pre-commit secret scanning. The scanner was scoped to staged changes only; pre-existing committed secrets were not detected."* W0-13 is exactly this incident, written in advance.

What the Pilot would have produced instead: with `~/.security-pilot/SKILLS/sec-precommit.md` in the agent's reasoning loop, the agent would have read the W0-13 row, recognized that staged-diff scanning alone is the documented anti-pattern, and produced a **two-layer setup** — fast `gitleaks protect --staged` for local commits *plus* a CI cron job running `gitleaks detect` against full history *plus* a documented `last_full_history_sweep_date` field in `PROJECT_PILOT.md`. The staging-key leak would have been surfaced at adoption time and rotated, *or* the audit row would have been explicitly open with a date marker showing the team knew the gap existed. Either outcome is a controlled state. Neither is the silent killer.

**Canonical fix:** (a) The hook performs **two** checks: (i) staged-diff scan as a fast gate, (ii) full-history scan as a slower CI job that runs on `push` and on a scheduled `cron`; (b) any pre-existing finding from the full-history scan is rotated *and* removed from history with `git filter-repo` (rotate-then-remove order — see W0-1) before the hook is declared "covering" the repo; (c) the W0 audit report explicitly states the date-of-last-history-sweep so reviewers know the gate's actual coverage window.
**PoC test shape:** `Test: a repo with a pre-existing committed AKIA-prefix in commit HEAD~50 fails the full-history scan in CI even when no current diff would trigger the staged-diff hook.`

#### W0-14 — `--no-verify` baked into a wrapper script or alias
**Severity:** High  *(normalized bypass; tooling defeats the gate by convention)*
**Maps to:** OWASP A04 · A05 · ASVS V1.1.4 · V14.2.4 · CWE-693 · CWE-807 · CWE-1059
**Symptom in code:** A `Makefile` with `commit: ; git commit --no-verify ...`, an npm script `"commit": "git commit -n ..."`, a developer's shell alias documented in CONTRIBUTING (`alias gc='git commit --no-verify'`), or a CI release script that invokes `git commit --no-verify` to land version bumps.
**Why it's wrong:** Hooks exist to slow down dangerous operations. Wrapping `--no-verify` into the team's standard tooling normalizes the bypass — every contributor who follows the README ends up bypassing the gate. The release-script case is especially bad: the one place where the most-trusted commits are made is the one place where the hook never runs. This is a documentation-and-tooling defect, not a code defect, which makes it slip through code review.
**Canonical fix:** (a) Audit removes `--no-verify` from every committed script, alias documentation, and CI workflow; (b) if a release flow genuinely cannot pass the hooks (rare; usually a sign the hook is over-broad), the script invokes the specific check it needs to skip with a structured exception, not a blanket bypass; (c) server-side enforcement (W0-11, W0-12) makes `--no-verify` locally moot — the push fails CI; (d) `PROJECT_PILOT.md` documents the policy: "no contributor or release flow uses `--no-verify`; if a hook needs an exception, fix the hook, don't bypass it."
**PoC test shape:** `Test: grep -rE '--no-verify|\\-n[ \"]' Makefile package.json scripts/ .github/workflows/ returns empty; if it returns any line, the W0 audit row is open.`

## PoC-Test Recipes — Iron Law Discipline

Every W0 control ships with a failing-then-passing PoC test. The recipes below are the canonical shapes for the two hook frameworks the user community uses most: Husky (Node ecosystem) and native git hooks (everything else, including Go, Python, and Helm-only repos).

### Recipe A — Husky

Husky stores hooks in `.husky/` and uses git's `core.hooksPath`. The PoC test shape uses `bats` (or `vitest` for pure-Node setups) to invoke a temporary git repo, attempt a known-bad commit, and assert the hook rejects it.

```bash
#!/usr/bin/env bats
# tests/precommit/secrets.bats — runs in CI, gated as a required check.

setup() {
  TMP="$(mktemp -d)"
  cd "$TMP"
  git init --quiet
  cp -r "$BATS_TEST_DIRNAME/../../.husky" .
  cp "$BATS_TEST_DIRNAME/../../package.json" .
  npm install --silent
  npx husky install
  git add -A && git commit --quiet -m "init" || true
}

teardown() { rm -rf "$TMP"; }

@test "W0-1: rejects commit adding .env with AWS access key" {
  echo 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' > .env
  git add .env
  run git commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"AKIA"* ]] || [[ "$output" == *"secret"* ]]
}

@test "W0-1: accepts commit with .env.example documenting the variable name" {
  echo 'AWS_ACCESS_KEY_ID=' > .env.example
  git add .env.example
  run git commit -m "should pass"
  [ "$status" -eq 0 ]
}
```

Three rules for Husky PoC tests:
1. **Run in a fresh tmp-repo** so the test has no dependency on the host repo's history.
2. **Assert both negative and positive cases.** A hook that rejects everything is also broken.
3. **Match the CI re-execution pattern.** The same `bats` file runs in `.github/workflows/precommit.yml`; the gate's local and CI behavior must be identical or the gap is a finding (W0-12).

### Recipe B — Native git hooks (no framework)

For repos that do not adopt `pre-commit`, `husky`, or `lefthook`, native hooks live in `.git/hooks/` (per-clone, not committed) or under a versioned directory pointed to by `core.hooksPath`. The versioned form is the only auditable one.

Project layout:
```
hooks/                       # versioned, points-to via core.hooksPath
  pre-commit                 # bash; calls scanners; exits non-zero on detection
  pre-push                   # bash; full-history sanity sweep before push
tests/precommit/
  test_pre_commit.sh         # runnable via `make test-hooks` and in CI
```

`tests/precommit/test_pre_commit.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

run_in_tmp_repo() {
  local script="$1"
  local tmp; tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN
  (
    cd "$tmp"
    git init --quiet
    git config core.hooksPath "$PWD/hooks"
    cp -r "$REPO_ROOT/hooks" .
    bash -c "$script"
  )
}

# W0-1 negative case: must FAIL
REPO_ROOT="$(git rev-parse --show-toplevel)"
if run_in_tmp_repo '
  echo "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF" > .env
  git add .env
  git commit -m "leak" 2>&1
'; then
  echo "FAIL: hook accepted a committed AWS key" >&2
  exit 1
fi
echo "OK W0-1 negative: hook rejected AKIA in .env"

# W0-1 positive case: must PASS
if ! run_in_tmp_repo '
  echo "# Documented variables" > .env.example
  git add .env.example
  git commit -m "doc" 2>&1
'; then
  echo "FAIL: hook rejected a legitimate .env.example commit" >&2
  exit 1
fi
echo "OK W0-1 positive: hook accepted .env.example"
```

Three rules for native-hook PoC tests:
1. **Use `core.hooksPath`, not `.git/hooks/` directly.** Hooks under `.git/hooks/` are per-clone and untestable; hooks under a versioned directory pointed to by `core.hooksPath` are committed and reviewable.
2. **Verify the redirect is set.** A separate test asserts `git config --get core.hooksPath` returns the expected path. A repo where the redirect was never set is a repo where the hooks never ran — silent failure is the most expensive mode.
3. **Run in CI as a required check.** The native-hook recipe is only enforcement if CI re-executes it on pushed refs (see W0-12).

## Bypass-Resistance Checklist — CI / CD Enforcement

Local hooks are advisory until the server enforces them. This checklist is the audit row that converts "we have hooks" into "the gate is unbypassable in normal flow."

- [ ] **CI runs the same hooks as local.** `.github/workflows/precommit.yml` (or Woodpecker / GitLab equivalent) invokes `pre-commit run --from-ref ... --to-ref ...` against the pushed delta and `--all-files` on `pull_request`. Pinned to the same `rev:` versions as local installs.
- [ ] **The CI job is a required status check.** Branch-protection rules on the protected branch (`main`, `release/*`) reject merges where the pre-commit CI job did not succeed. Verified via `gh api repos/<org>/<repo>/branches/main/protection` (or `tea repos --remote origin show` for Gitea/Forgejo).
- [ ] **`--no-verify` does not ship.** A separate CI step `grep -rE '\-\-no-verify|\\-n[ \"]' Makefile package.json scripts/ .github/workflows/` returns empty (W0-14). Any occurrence is an open W0 finding.
- [ ] **Force-push to protected branches is restricted to break-glass roles.** `git push --force` to `main` would let an attacker rewrite history past a passing pre-commit check. Branch protection enforces "Restrict who can push to matching branches" with no `--force`-allowed identities outside the documented break-glass role.
- [ ] **Full-history sweep runs on a schedule, not only on diff.** A scheduled CI workflow (daily / weekly) runs `gitleaks detect --redact` (or equivalent) on the entire repo, not the staged diff. W0-13 specifically targets repos that scan only the diff.
- [ ] **Hook-implementation pins are reviewed.** Renovate / Dependabot updates `rev:` pins via PR; the pinned version is verifiable against signed tags or signed commit SHAs (W0-10).
- [ ] **The W0 posture is documented.** `<project>/.security-pilot/PROJECT_PILOT.md` includes a Wave 0 section: which framework, which hooks, which CI job, last full-history sweep date, and the documented exception process (which is "fix the hook" — never `--no-verify`).
- [ ] **Server-side secret-scanning is enabled.** GitHub: Advanced Security secret-scanning + push protection. Gitea/Forgejo: equivalent (`gitleaks` in CI is the fallback). The server-side check is a backstop for cases where the CI job is misconfigured.

A repo passes Bypass-Resistance only when **every** box is checked. A partially-checked posture is a finding, not a state.

## Finding template (use exactly this structure)

```markdown
### W0-<n> — <one-line title>

**Severity:** Critical | High | Medium | Low | Info  *(definitions in PILOT.md)*
**Maps to:** OWASP A0X · ASVS V0X.X · CWE-XX · W0-<row-id>
**File / config:** `<path>` (or `repository setting: branch protection`)
**Status:** open

**Vulnerability**
What is wrong, in one paragraph. Cite the specific construct and why it violates the cited standard.

**Real-world impact**
A real incident, post-mortem, or industry-benchmark report demonstrating this defect's exploitation. Per the project's Contributing rule, every footgun row cites at least one credible primary or industry source.

**Remediation strategy**
Wave: W0  *(this skill)*
The fix shape, plus the bypass-resistance step that makes the local fix actually enforced.

**Verification test**
Failing test that gates the fix (Iron Law PoC). One-line description here; full test code lives in `tests/precommit/`.
```

## Anti-patterns this skill rejects

- A finding without a citation. "Best practice" is not a citation.
- A "we use pre-commit hooks" claim with no CI re-execution evidence. Local-only enforcement is theatre (W0-11, W0-12).
- Recommending a hook without a PoC test that proves it would catch the bad input. Iron Law applies to W0 controls, not just W1–W4 fixes.
- Treating `--no-verify` as a normal contributor tool. It is a break-glass operation; bake it into tooling at your peril (W0-14).
- Removing a committed secret from history *before* rotating it. The rotation window is the leak (W0-1).
- Scanning only staged diffs and declaring the repo covered. Full-history sweep is non-negotiable (W0-13).
- Pinning hook implementations to floating refs. The hook is the gate; the gate must not move under the team (W0-10).

## TODO before this skill is cut from `3.1.0-alpha` to non-alpha `3.1`

1. **Citation review.** Two of the real-world-impact citations (Mercedes-Benz 2024, Toyota 2022 disclosure dates) need a primary-source link from a security advisory or a credible incident-response writeup before this file goes GA.
2. **Validation on a reference project.** All 14 PoC-test recipes need to run end-to-end against a fresh test repo, in CI, with both Husky and native-hook variants. Currently only structurally drafted.
3. **Adapter notes for `pre-commit` (Python) and `lefthook`.** This draft covers Husky and native hooks per the user's explicit scope; the other two frameworks have non-trivial differences (e.g., `pre-commit`'s isolated venvs change the failure-mode for missing dependencies) and need their own recipes before the skill claims framework-agnostic coverage.
4. **Severity calibration.** ✓ Assigned in v3.1-alpha. Distribution: **5 Critical** (W0-1, W0-2, W0-3, W0-5, W0-13) — direct credential exposure or load-bearing false-security; **6 High** (W0-4, W0-9, W0-10, W0-11, W0-12, W0-14) — significant compromise with conditions, or enforcement-gap classes; **3 Medium** (W0-6, W0-7, W0-8) — defense-in-depth and supply-chain-conditional rows. Re-review at the non-alpha cut against any post-validation findings; W0-4 (Helm) explicitly flips to Critical on public repos.
5. **Cross-reference into `framework-footguns.md`.** The Next.js (`W0-2`) and Drizzle (`W0-3`) rows want sibling entries in the framework footgun library so `/sec-audit` cites them on application-layer audits too.
6. **Cut canonical pilot from `3.1.0-alpha` to `3.1`** once items 1–5 are complete and reviewed.
