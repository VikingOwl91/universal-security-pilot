# sec-container — Wave 5: Container / OCI Image Hardening

> **STATUS: v3.1-alpha WORKING DRAFT.** Citation map, footgun catalogue (12 rows), PoC-test recipes (`dive` + `container-structure-test`), and provenance-verification checklist are in place. **Not yet GA** — recipes have not been validated end-to-end on a reference image, and several CVE / advisory citations need primary-source review. Do not invoke against production audits until the canonical pilot is cut from `3.1.0-alpha` to a non-alpha `3.1`.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 5 audits the **build artifact** — the OCI image produced by the project's Dockerfile (or Buildpack, ko, Jib, nixpacks, etc.). It runs after W1–W4 (application-layer fixes) and before W6 (orchestration). The image is the unit of deployment; an image that runs as root, pulls a `:latest` base, or carries build-time toolchains and secrets into the runtime stage is an attack surface no orchestration policy can fully mitigate.

W5 depends on **W0** being satisfied (a Dockerfile committed without W0 lint may already carry an anti-pattern at the source) and **W3** (any secret material the application needs at runtime must be stored per W3's envelope-encryption rules — never baked into the image). Findings in W5 reduce to "the build pipeline produced a bad artifact"; W6 then audits "the runtime is configured to run that artifact safely."

## What this skill produces

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-container.md` with:

- The W5 audit report header (date, image refs, registry topology, threat model: who can pull, who can push, who runs the consumer admission).
- Per-finding rows using the template at the bottom of this file.
- A Wave-5 remediation order (blast-radius descending: secrets-in-layers > root + missing isolation > unsigned image > unpinned base > metadata gaps).
- A "tests to write first" list — every W5 fix ships with a failing PoC test per the Iron Law.

## When to use

- "Audit our Dockerfiles before we publish to the registry."
- Any change to a Dockerfile, base image, or build pipeline.
- Pre-cutover from a private to a public registry (severity calibration shifts).
- Post-incident review when a runtime escape, layer extraction, or registry compromise is suspected.
- After adopting a new build tool (Buildpack, ko, Jib, nixpacks) — these have different default postures.

## When NOT to use

- Single dependency bump in `package.json` / `go.mod` with no Dockerfile change.
- Pure application-code review — that is W1–W4 territory.
- Buildpack-only or `ko`-only projects where no Dockerfile exists; W5 still applies, but the audit shape changes (note in scope) and several rows below need adapter notes that are not yet in this draft.

## Pre-audit grounding

1. **Inventory the build artifacts.** Every Dockerfile, ko config, Jib plugin spec, Buildpack builder spec. Multi-arch manifest lists are one logical artifact; single-arch is one too.
2. **Identify the registry topology.** Public (Docker Hub, GHCR public) vs. private (ECR, GHCR private, internal Harbor / Nexus / Gitea). Severity calibration depends on this — `W5-10` (ENV with secret) is High on a private registry, Critical on a public one.
3. **Walk the image with `docker history --no-trunc <image>`.** Note any layer with secret-pattern matches, large `COPY` surfaces, or unexpected `RUN` invocations.
4. **Resolve all `FROM` digests.** Any base image referenced by tag only must be resolved to its current digest; the audit captures both for drift tracking.
5. **Confirm registry signing posture.** Cosign signatures present? SBOM emitted? SLSA provenance attestation? Absence of any is a finding *before* reading the Dockerfile.
6. **Check W0 prerequisites.** A Dockerfile that fails W0 lint cannot be audited under W5 in isolation — fix the W0 finding first, rebuild, re-audit.

## Citation Map — OWASP / ASVS / CWE / CIS Docker Benchmark / NIST SP 800-190

| Category | OWASP Top 10 (2021) | OWASP ASVS L2 | CWE | CIS Docker Benchmark | NIST SP 800-190 |
|---|---|---|---|---|---|
| Multi-stage / build leakage | A05 Security Misconfig · A08 Software & Data Integrity Failures | V14.2.1 (build process) · V14.2.4 (build pipeline integrity) · V14.3.2 (hardening defaults) | CWE-540 Inclusion of Sensitive Information · CWE-200 Information Disclosure · CWE-1357 Reliance on Insufficiently Trustworthy Component | 4.6 (Add HEALTHCHECK) · 4.10 (no secrets in Dockerfile) · 5.31 (no privileged Docker API) | §4.4 (image), §4.5 (registry) |
| Non-root enforcement | A05 | V14.2.1 · V14.3.2 | CWE-250 Execution with Unnecessary Privileges · CWE-269 Improper Privilege Management · CWE-732 Incorrect Permission Assignment | 4.1 (Run as non-root) · 5.4 (Restrict containers from acquiring new privileges) | §4.4.1, §4.4.4 |
| Image pinning / provenance | A05 · A06 Vulnerable & Outdated Components · A08 | V14.2.1 · V10.3.2 (data integrity) | CWE-1357 · CWE-353 Missing Support for Integrity Check · CWE-345 Insufficient Verification of Authenticity | 4.2 (Use trusted base images) · 4.5 (use COPY not ADD) | §4.5.1 (image-pull integrity) |
| Sensitive data in layers | A02 Cryptographic Failures · A07 Identification & Auth Failures | V14.1.5 (no inline secrets) · V8.3.4 (sensitive data not logged) · V2.10.4 (no inline secrets in source) | CWE-798 Use of Hardcoded Credentials · CWE-540 · CWE-522 Insufficiently Protected Credentials · CWE-200 | 4.10 | §4.4.5 |

Standard citation line:
```
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-250 · CIS Docker 4.1 · NIST SP 800-190 §4.4.1 · W5-4
```

## Footgun Catalogue — Wave 5

Each row uses the framework-footguns block format: **Severity · Maps to · Symptom · Why wrong · Canonical fix · PoC test shape.**

### Category W5-A — Multi-Stage Build Hygiene

#### W5-1 — Final stage inherits from the builder stage instead of a minimal base
**Severity:** High  *(ships entire build environment to runtime; CVE surface multiplied)*
**Maps to:** OWASP A05 · A06 · ASVS V14.2.1 · CWE-1357 · CIS Docker 4.6 · NIST SP 800-190 §4.4
**Symptom in code:** Dockerfile with `FROM <heavy-base> AS builder` ... `FROM builder AS runtime` (final stage's `FROM` is the builder), or a single-stage Dockerfile that produces the runtime image directly from a `node:20`, `python:3.12`, or full-distribution base.
**Why it's wrong:** Multi-stage builds exist to discard build-time scaffolding from the final image. When the final stage's `FROM` is the builder (or any heavy base inheriting from it), every compiler, package manager, and toolchain dependency travels into production. A `node:20` base ships with `npm`, `npx`, `node-gyp`, glibc dev headers, and ca-certificates; a `gcr.io/distroless/nodejs20` reduces the package count by an order of magnitude. The pattern recurs because a single-stage Dockerfile builds correctly for development, and the multi-stage refactor is treated as an optimization rather than a security primitive. Build-tool CVEs (npm 2022 CVE-2022-29244 path-traversal, pip 2023 CVE-2023-5752 wheel verification) become runtime-relevant only when the build tool is in the runtime image.
**Canonical fix:** (a) Final stage uses a deliberately minimal base — `gcr.io/distroless/<lang>`, `scratch`, or `alpine` (only when shell access is genuinely required); (b) `COPY --from=builder` brings only the compiled artifacts, not the source tree or the package cache; (c) build-time deps execute in the builder stage only and are absent from the final image; (d) `docker history <image>` post-build shows zero `RUN` steps invoking package managers in the final-stage layers.
**PoC test shape:** `Test: container-structure-test asserts /usr/bin/npm and /usr/bin/gcc do NOT exist in the final image; docker history <image> | grep -cE 'RUN.*(npm|pip|apt|apk).*install' returns 0 in the final-stage layer set.`

#### W5-2 — `COPY .` without strict `.dockerignore`
**Severity:** High  *(drags `.env`, `.git`, secrets, node_modules, build artifacts into layers)*
**Maps to:** OWASP A05 · A07 · ASVS V14.1.5 · CWE-540 · CWE-200 · CIS Docker 4.10
**Symptom in code:** Dockerfile contains `COPY . /app/` (or `COPY . .`) without a `.dockerignore` at the build-context root that excludes `.env*`, `.git/`, `node_modules/`, `__pycache__/`, build artifacts, and any `secrets/` or `keys/` directory.
**Why it's wrong:** `COPY .` ships every file in the build context. Without `.dockerignore`, that includes `.env` files (still in the working tree at build time even if gitignored), `.git/` (exposes commit history *and* any historical secrets in HEAD~∞ — see W0-13), `node_modules/` (bloats image, ships dev-only packages with their CVE surface), `*.pem` keys, AWS config files, and anything else a developer happens to have in the working tree. The image then ships those files to every consumer. Even if the runtime entrypoint never reads them, `docker cp <container>:/app/.env -` extracts them in seconds.
**Canonical fix:** (a) `.dockerignore` at the repo root explicitly excludes `**/.env*`, `**/.git/`, `**/node_modules/`, `**/__pycache__/`, `**/.pytest_cache/`, `**/dist/`, `**/build/`, `**/*.pem`, `**/*.key`, `**/secrets/`, `**/keys/`, `**/.aws/`, `**/.ssh/`; (b) `COPY` instructions are narrow (`COPY package*.json ./`, `COPY src/ ./src/`) rather than wholesale; (c) post-build verification: `docker run --rm <image> ls -la /app | grep -E '(\.env|\.git|secrets)'` returns empty.
**PoC test shape:** `Test: a build context with a planted .env file produces an image where docker run --rm <image> cat /app/.env fails with "No such file or directory"; the same build with .dockerignore removed produces an image where the file is readable.`

#### W5-3 — Build cache mounts leak credentials across builds
**Severity:** High  *(cache-shared credentials persist beyond the originating build; multi-tenant amplifier)*
**Maps to:** OWASP A07 · A08 · ASVS V14.1.5 · V14.2.4 · CWE-522 · CWE-540
**Symptom in code:** Dockerfile uses `RUN --mount=type=cache,target=/root/.npm ...` or `--mount=type=cache,target=/root/.cache/pip` (or equivalent for go, cargo, gradle) where the cache target may contain authenticated package-manager state (`.npmrc` with `_authToken`, `.pip/pip.conf` with credentialed `index-url`, `.cargo/credentials.toml`).
**Why it's wrong:** BuildKit cache mounts are persisted across builds on the same builder, intentionally — that is their performance value. But package-manager auth state is sometimes stored within the cache directory itself, and credentials stored there persist into subsequent builds, including builds invoked by different user sessions on the same builder. A CI runner that builds for tenant A and then tenant B can leak A's npm auth token into B's cache mount. The defect compounds with shared CI infrastructure: a self-hosted GitHub Actions runner serving multiple repos, a Woodpecker runner shared across orgs, a GitLab Runner with `concurrent > 1` and no isolation.
**Canonical fix:** (a) Cache mounts target only the artifact cache, not the credential surface — `target=/root/.npm/_cacache` (just the package store) rather than `target=/root/.npm` (whole config); (b) auth secrets enter the build via `--mount=type=secret,id=npmrc,target=/root/.npmrc` (BuildKit-managed, not persisted in any layer); (c) CI builders are scoped per tenant — a shared builder is a finding by itself in any multi-tenant build infrastructure; (d) the cache mount is scoped per project via `id=<proj>-npm-cache` so cross-project bleed is structurally impossible.
**PoC test shape:** `Test: build image A with --secret id=npmrc,src=A.npmrc, then build image B with --secret id=npmrc,src=B.npmrc; inspect B's cache mount via a debug RUN — A's auth token must not be present.`

### Category W5-B — Non-Root Enforcement

#### W5-4 — No `USER` directive (final stage runs as root)
**Severity:** Medium  *(defense-in-depth gap; blast-radius amplifier on container escape)*
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-250 · CWE-269 · CIS Docker 4.1 · NIST SP 800-190 §4.4.1
**Symptom in code:** Dockerfile final stage has no `USER <uid>` directive before `CMD` / `ENTRYPOINT`.
**Why it's wrong:** Containers without `USER` run as UID 0. The runtime layer (W6) can constrain via `runAsNonRoot: true` admission, but defense-in-depth says: catch at the source. CVE-2024-21626 ("leaky vessels", runC <1.1.12, January 2024) demonstrated that a kernel-level container escape is feasible from root-running containers; the same exploit attempt from a non-root user fails at multiple checkpoints. Combined with W5-2 (COPY . dragging secrets), a root-running container with sensitive layer content is an order-of-magnitude worse than either defect alone. The fix is one line in the Dockerfile.
**Canonical fix:** (a) `USER 10001:10001` (numeric UID:GID — see W5-5 for *why* numeric); (b) any directories the app writes to are pre-created and `chown 10001:10001`'d in a `RUN` invoked while still `USER root`, then the `USER` switch happens; (c) `docker run --rm <image> id -u` returns a non-zero UID; (d) Kubernetes admission policy (W6) enforces `runAsNonRoot: true` and `runAsUser: 10001` as backstops.
**PoC test shape:** `Test: docker run --rm <image> id -u returns a value >= 1000; the assertion is wired into container-structure-test as a commandTest with expectedOutput regex ^[1-9][0-9]{3,}$.`

#### W5-5 — `USER` directive uses a name, not a numeric UID
**Severity:** Medium  *(Kubernetes runAsNonRoot can't verify; image layout drift breaks identity)*
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-732 · CIS Docker 4.1
**Symptom in code:** `USER node`, `USER nginx`, or `USER appuser` in the Dockerfile, where the user name resolves via the image's `/etc/passwd`.
**Why it's wrong:** Kubernetes `runAsNonRoot: true` admission checks the *numeric* UID at admission time — without a `runAsUser: <uid>` override or a numeric Dockerfile USER, the policy must read `/etc/passwd` *inside* the image to verify, which is brittle and runtime-late. Worse, the named user's UID can vary across base-image versions or distributions; an `alpine:3.18` `node` user may have UID 1000 while a `node:20-slim` `node` is UID 1001, and silent drift between rebuilds turns into "the container ran as a different identity than the policy thought." Numeric UIDs are stable; names are not. Admission policies that key on UID (e.g., `runAsUser: 1000` to allow only that identity) silently fail-open when the named user's UID drifts to a different value.
**Canonical fix:** (a) `USER 10001:10001` (numeric UID:GID, the team's chosen non-root identity, deliberately above the typical distro range to avoid collision); (b) the Dockerfile creates the user with `RUN groupadd -g 10001 app && useradd -u 10001 -g 10001 -s /sbin/nologin -d /app app` (or distroless equivalent — most distroless images already include a `nonroot` user at UID 65532); (c) Kubernetes manifest mirrors with `runAsUser: 10001` and `runAsNonRoot: true`; (d) the chosen UID is documented in `PROJECT_PILOT.md` so cross-image consistency is auditable across services.
**PoC test shape:** `Test: docker inspect --format='{{.Config.User}}' <image> returns a string matching ^[0-9]+(:[0-9]+)?$ (numeric only); a USER directive of "node" fails this assertion.`

#### W5-6 — Non-root user reverted to root because the app needed write access
**Severity:** High  *(silent regression; the "fix" reintroduces the original defect under a misleading commit message)*
**Maps to:** OWASP A05 · A04 Insecure Design · ASVS V14.3.2 · V1.1.4 · CWE-250 · CWE-693
**Symptom in code:** Git history showing a commit that adds `USER 10001`, followed weeks later by a commit that removes it (or replaces it with `USER root`) with a commit message like "fix: container permissions" or "fix: cannot write to /var/log/app/" — or a Dockerfile with `USER root` immediately before `CMD` "to fix permissions issues."
**Why it's wrong:** This is the multi-step regression: somebody added the non-root USER (W5-4 fix), the app failed at runtime because it needed to write to `/var/log/app/`, `/data/`, or `/.cache/`, and the fastest "fix" was to revert to root. The original blast-radius problem is back, but now under a misleading commit message. Code review usually does not catch this because the diff looks small and the reasoning ("permissions issue") is plausible. The defect class is rationalization-under-deadline, exactly what PILOT.md's rationalization-counter table addresses. Reviewers reading "fix: container permissions" do not naturally connect it to "we just disabled defense-in-depth."
**Canonical fix:** (a) The Dockerfile pre-creates and `chown 10001:10001`s every directory the non-root user needs to write — `RUN mkdir -p /var/log/app /data /home/app/.cache && chown -R 10001:10001 /var/log/app /data /home/app`; (b) the non-root USER is the *last* `USER` directive — no later reverts; (c) PR review checklist asks "did this PR reduce the running UID toward 0?" — any reduction is rejected without an explicit security-exception note in the commit body and a follow-up issue to restore non-root; (d) CI runtime test asserts `id -u` returns the documented non-root UID, gating the merge.
**PoC test shape:** `Test: a hypothetical PR introducing USER root before CMD fails a CI policy check that greps the merge-base diff for ^USER (root|0)$ in the final stage; the assertion runs on the diff, not just the file at HEAD.`

### Category W5-C — Image Pinning & Provenance

#### W5-7 — `FROM` with mutable tag (no `@sha256` digest pin)
**Severity:** Medium  *(supply-chain risk; complementary to W0-7's pre-commit lint at the artifact policy layer)*
**Maps to:** OWASP A05 · A06 · A08 · ASVS V14.2.1 · CWE-1357 · CWE-353 · CIS Docker 4.2
**Symptom in code:** `FROM node:20-alpine` (any tag without `@sha256:<64hex>`), especially `:latest`, `:lts`, or floating major-version tags. W0-7 catches the pattern at commit time; W5-7 catches it at the artifact policy level — the published image was built from a tag-only base and there is no record of which digest the tag resolved to at build time.
**Why it's wrong:** Tags are mutable refs. The `node:20-alpine` you tested is not necessarily the `node:20-alpine` you ship next week. Legitimate base-image updates (security patches) flip the digest under the same tag — usually fine, but auditable only if the digest was captured before the update. Compromise (registry account takeover, key leak, mirror substitution) flips the digest under the same tag — and there is no audit trail. The 2021 Codecov bash uploader incident (CVE-2021-32638) and the broader pattern of registry / mirror substitution underline that tag-only pinning is "trust the registry," not "verify the artifact." The discipline scales: every base image, including build-stage images, must be digest-pinned.
**Canonical fix:** (a) `FROM node:20-alpine@sha256:<64hex>` — digest plus human-readable tag (the tag is documentation; the digest is enforcement); (b) Renovate or Dependabot opens PRs to update the digest, so updates are reviewable rather than silent; (c) the build-time toolchain verifies the digest matches the policy file (`renovate.json`, `.github/dependabot.yml`) before the build proceeds; (d) `docker buildx imagetools inspect <image>` is captured at every release-tag build and committed to the artifact catalog so cross-build drift is detectable.
**PoC test shape:** `Test: a Dockerfile with FROM node:20-alpine (no digest) fails a CI policy check; the same file with FROM node:20-alpine@sha256:<64hex> passes; a build whose registry-resolved digest differs from the pinned value fails.`

#### W5-8 — No SBOM (CycloneDX or SPDX) emitted at build
**Severity:** Medium  *(post-incident debugging blind; CVE-response loses the audit trail)*
**Maps to:** OWASP A06 · A08 · ASVS V14.2.1 · V10.3.2 · CWE-1357 · NIST SP 800-218 (SSDF), NIST SP 800-190 §4.5.1
**Symptom in code:** Build pipeline (`docker buildx build` invocation, CI workflow) without `--sbom=true` (BuildKit ≥0.11) or an equivalent `syft <image> -o spdx-json` step; image manifests on the registry without `application/vnd.cyclonedx+json` or `application/spdx+json` media types attached.
**Why it's wrong:** When the next critical CVE hits, the question "are we affected?" is answered by SBOM lookup in seconds — *if* an SBOM exists. Without an SBOM, the team is reduced to manually rebuilding an image at the deployed digest and running `dpkg -l` / `pip freeze` / `npm ls --all` to enumerate components. Hours of work per image, brittle, and the rebuild may not reproduce exactly. The Log4Shell (CVE-2021-44228, December 2021) response demonstrated the gap at scale: teams with SBOMs answered the question in minutes; teams without spent days, sometimes longer for transitively-bundled cases. SBOM is not a feature; it is an audit-trail prerequisite.
**Canonical fix:** (a) `docker buildx build --sbom=true --provenance=true ...` (or `syft <image> -o cyclonedx-json` as a CI step for builders that don't support BuildKit attestations); (b) the SBOM is attached to the registry artifact (`oras attach` or BuildKit's automatic attestation manifest); (c) consumer admission (W6) verifies SBOM presence as a gating policy — no SBOM, no scheduling; (d) the SBOM format is consistent across the org (CycloneDX *or* SPDX, picked once and pinned) so the CVE-response tooling has one parser to maintain.
**PoC test shape:** `Test: cosign tree <image-ref> shows an attestation of type https://cyclonedx.org/bom (or https://spdx.dev/Document) AND an attestation of type https://slsa.dev/provenance/v1; absence of either is a finding.`

#### W5-9 — No cosign signature on the published image
**Severity:** Medium  *(no cryptographic chain of custody; admission cannot enforce origin)*
**Maps to:** OWASP A05 · A08 · ASVS V10.3.2 · CWE-345 · CWE-353 · NIST SP 800-190 §4.5.1
**Symptom in code:** CI workflow that runs `docker push` (or `buildx --push`) without a subsequent `cosign sign` step; admission policy on the consumer side (W6) that does not verify a signature.
**Why it's wrong:** Without a signature, the image is "whatever the registry serves." A registry compromise, mirror substitution, or DNS hijack can serve a different image at the same name — and the consumer has no way to detect. Cosign keyless signing (Fulcio + Rekor) provides a cryptographic binding from the image to the OIDC identity that built it, with a transparency log; verification is a single `cosign verify` call. The pattern is not GA across all registries (some only support OCI-spec attestations, not cosign), but for any registry that supports it, absence is a finding. Signed-but-unverified is *also* a finding — the chain is only as strong as its weakest link, and an admission policy that doesn't enforce verification is decoration.
**Canonical fix:** (a) CI workflow appends `cosign sign --yes <image-ref>@<digest>` after push, using OIDC identity (GitHub Actions, GitLab CI, Woodpecker via OIDC); (b) consumer admission policy (sigstore policy-controller, Kyverno `verifyImages`, Connaisseur) verifies the signature against an allowlisted Fulcio CA + Rekor log + OIDC identity pattern; (c) the verification policy is required at admission, not advisory — `enforce` mode, not `audit` mode.
**PoC test shape:** `Test: cosign verify --certificate-identity-regexp '<expected-ci-identity>' --certificate-oidc-issuer '<expected-issuer>' <image>@<digest> succeeds for a properly-signed image; an unsigned image (or one signed by an unexpected identity) fails verification.`

### Category W5-D — Sensitive Data in Image Layers

#### W5-10 — `ENV` used to bake credentials or tokens into the image
**Severity:** High  *(credentials persist in image config and history; visible to anyone who can pull)*
**Maps to:** OWASP A07 · A02 · ASVS V14.1.5 · V8.3.4 · CWE-798 · CWE-540
**Symptom in code:** `ENV API_KEY=sk_live_...`, `ENV DATABASE_PASSWORD=...`, `ENV STRIPE_SECRET=...` in a Dockerfile; or `ENV` set from a `--build-arg` whose value is a real credential.
**Why it's wrong:** `ENV` values are stored in the image config, readable by anyone who can pull the image: `docker inspect <image> --format='{{json .Config.Env}}'` returns the full list with values. They also appear in `docker history` and persist in every layer that follows the `ENV` line. The value is part of the image — rotating the secret means rebuilding and republishing the image, and every prior pull of the previous image still has the old credential. ASVS V14.1.5 is unambiguous: secrets are not stored in build artifacts. The defect compounds when images are pushed to a public registry; the secret is then world-readable, not merely org-readable.
**Canonical fix:** (a) Application reads secrets from the runtime environment (Kubernetes Secret mounted via env or volume), not from `ENV` baked into the image; (b) build-time secrets needed *only* during build use `--mount=type=secret,id=...,target=...` (BuildKit-managed; not persisted in any layer); (c) the W5 audit greps `docker inspect <image> --format='{{json .Config.Env}}'` for known secret-pattern regex (`AKIA[A-Z0-9]{16}`, `sk_live_[a-zA-Z0-9]{24,}`, `ghp_[a-zA-Z0-9]{36}`, `glpat-[a-zA-Z0-9_-]{20}`) and fails on any match.
**PoC test shape:** `Test: docker inspect --format='{{json .Config.Env}}' <image> | grep -E '(AKIA[A-Z0-9]{16}|sk_live_|ghp_|glpat-)' returns empty; the same image built with ENV STRIPE_SECRET=sk_live_test fails the assertion.`

#### W5-11 — `ARG` used as a build-time secret
**Severity:** High  *(build args persist in image history; "looks safer than ENV" intuition makes this defect persist)*
**Maps to:** OWASP A07 · A02 · ASVS V14.1.5 · V14.2.4 · CWE-798 · CWE-540
**Symptom in code:** `ARG NPM_TOKEN`, `ARG STRIPE_SECRET`, `ARG GITHUB_TOKEN` (followed by `RUN npm install` or `RUN curl -H "Authorization: ..."` that uses the value), with the value provided via `docker build --build-arg NPM_TOKEN=...`.
**Why it's wrong:** This pattern is *more* common than W5-10 because devs know "ENV is in the image" and reach for ARG as the workaround. But ARG values appear in `docker history --no-trunc <image>` (the build command is recorded in the layer's `created_by` field), in BuildKit cache layers when `--cache-to` / `--cache-from` is used, and in `docker inspect` outputs depending on the builder. The Docker documentation explicitly recommends `--mount=type=secret` for credential material; `--build-arg` was never designed as a secrets mechanism. The "looks safer than ENV" intuition is exactly what makes this defect persist — devs feel they did the right thing while the secret still leaks.
**Canonical fix:** (a) Replace ARG-based secret-passing with `RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm install` (BuildKit-managed; the secret is mounted as a file, never written to a layer, never recorded in history); (b) the secret enters the build via `docker buildx build --secret id=npmrc,src=$HOME/.npmrc ...` rather than `--build-arg`; (c) post-build verification: `docker history --no-trunc <image>` shows no occurrence of the secret value or the ARG name in any layer's `created_by` field.
**PoC test shape:** `Test: docker history --no-trunc <image> | grep -E '(NPM_TOKEN|sk_live_|AKIA|ghp_)' returns empty; the same image built with --build-arg NPM_TOKEN=test123 fails the assertion (the value appears in history).`

#### W5-12 — `COPY <secret>` followed by `RUN rm <secret>` (the silent killer)
**Severity:** Critical  *(layer-extraction defeats the cleanup; the "fix" is theatre)*
**Maps to:** OWASP A07 · A02 · ASVS V14.1.5 · V8.3.4 · CWE-798 · CWE-540 · CWE-200
**Symptom in code:** Dockerfile sequence like `COPY secrets/ /tmp/build-secrets/` followed by `RUN ./build.sh && rm -rf /tmp/build-secrets/`; or `COPY ./id_rsa /root/.ssh/id_rsa` followed by `RUN ssh-add ... && rm /root/.ssh/id_rsa`; or `COPY .npmrc /root/.npmrc` followed later by `RUN rm /root/.npmrc`.
**Why it's wrong:** This is the **most insidious** W5 defect — analogous to W0-13 in pre-commit. The Dockerfile *looks* careful: there is an explicit cleanup line. The dev believes the secret is gone. But Docker layers are immutable filesystem snapshots: every `RUN`, `COPY`, `ADD` creates a new layer with the cumulative state at that point. The `rm` creates a *later* layer where the file is absent, but the *prior* layer still contains the file. Anyone with image-pull access can extract any earlier layer (`docker save <image> -o img.tar && tar -xf img.tar`, then `tar -xzOf <layer-blob>` to read each layer's filesystem; `dive <image>` shows the same; `crane export <image>:<digest>@<layer-digest>` is even faster). The cleanup is illusion. The pattern recurs because shell experience teaches "rm deletes," and the layer-immutability model is non-obvious to anyone who hasn't read the OCI image-spec. PILOT.md's W0-13 has the same shape — looks correct, isn't, and code review can't catch it from the Dockerfile alone.

**Real-world scenario (the silent killer in action):**

A SaaS team buys access to a vendor's private npm registry to install the vendor's TypeScript SDK (`@vendor/payments-sdk`). Installation requires a `.npmrc` file containing `//registry.vendor.com/:_authToken=<long-lived-token>`. The team asks their AI coding assistant: *"Add `@vendor/payments-sdk` to our Dockerfile. Here's the `.npmrc` with our private-registry token."*

The assistant, without the Pilot in scope, produces what looks like a careful Dockerfile:

```dockerfile
FROM node:20-alpine@sha256:abc... AS runtime
WORKDIR /app
COPY package*.json ./
COPY .npmrc /root/.npmrc
RUN npm ci --omit=dev \
    && rm /root/.npmrc
COPY src/ ./src/
USER 10001
CMD ["node", "/app/src/server.js"]
```

The agent reports: *"The Dockerfile copies the `.npmrc`, runs `npm ci`, and removes the file in the same RUN before any later layer. The final image does not contain the token. Verified with `docker run --rm <image> cat /root/.npmrc` — `No such file or directory`."*

Final-filesystem check: green. Container-structure-test: green. The image ships to the team's private GHCR. Production traffic flows. Ticket closed.

The agent's "same RUN" reasoning is a misunderstanding of the image-spec. While `&& rm` does run inside the *same* RUN as `npm ci`, the **COPY of `.npmrc` on the line above is its own image layer**. That layer contains the token, fully intact, regardless of any later cleanup. `docker save <image>` produces a tar with every layer as a separate blob; any one is extractable on its own:

```bash
$ docker save acme/api:v2.4.1 -o img.tar && tar -xf img.tar
$ for layer in blobs/sha256/*; do
>   tar -xzOf "$layer" 2>/dev/null | grep -aoE '_authToken=\S+' \
>     && echo "  ^ found in: $(basename "$layer")"
> done
_authToken=npm_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890
  ^ found in: 9f3c6a2e1d4b7c8e9f0a1b2c3d4e5f6a...   # the COPY layer
```

Six months later, the team starts publishing images to a partner-shared registry for an integration deal. The partner's security team runs `dive` on the first image as part of their onboarding checks, sees the `.npmrc` layer, and flags the token within minutes. The vendor revokes the npm registry token within hours — and every CI pipeline across the org that depends on the private registry starts failing simultaneously. The post-mortem reads: *"We had `&& rm /root/.npmrc` inside the install RUN. We did not understand that the COPY on the previous line created a separate layer that no later cleanup could touch. The token was recoverable from any image we had ever pushed."*

What the Pilot would have produced instead: with `~/.security-pilot/SKILLS/sec-container.md` in the agent's reasoning loop, the agent would have read W5-12, recognized that any COPY of a credential leaves the credential in that layer regardless of subsequent cleanup, and produced one of two correct shapes:

```dockerfile
# Shape A — BuildKit-managed secret (recommended)
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci --omit=dev
# Built with: docker buildx build --secret id=npmrc,src=$HOME/.npmrc ...
```

```dockerfile
# Shape B — builder-stage isolation (when the secret must exist as a file across multiple RUN steps)
FROM node:20-alpine@sha256:abc... AS builder
COPY package*.json .npmrc ./
RUN npm ci --omit=dev

FROM node:20-alpine@sha256:abc... AS runtime
COPY --from=builder /app/node_modules /app/node_modules
# The builder stage with the .npmrc layer is discarded; only node_modules ships to runtime.
```

Either shape is auditable via the layer-walking scan in Recipe B; neither leaves the token recoverable from the published image. The `&& rm` cleanup intuition would have been recognized as the W5-12 anti-pattern *before* the first build shipped — not six months later in a partner's onboarding scan.

**Canonical fix:** (a) Build-time secrets enter via `--mount=type=secret`, never via `COPY`; the secret is a tmpfs mount that exists only for the lifetime of the `RUN`, never written to any layer; (b) when `COPY` of a sensitive directory is unavoidable (e.g., a vendor SDK whose installer expects a credential file at a fixed path), it happens in the **builder stage only**, and the final stage's `COPY --from=builder /app/built-artifact /opt/app/` brings only the compiled output — the prior layers exist only in the discarded builder stage; (c) post-build verification with `dive <image>` inspects every layer, asserting no secret-pattern match in any historical layer (not just the final filesystem); (d) any image rebuilt from a Dockerfile that previously had this pattern in a prior version must rebuild from a fresh base — the leaked layer might still be in the registry's manifest history under a different tag.
**PoC test shape:** `Test: a script that does docker save <image> | tar -x and greps every layer's filesystem (not just the final state) for known secret patterns returns zero matches; the same scan against an image built with COPY secret/.npmrc → RUN npm install && rm /root/.npmrc fails (the .npmrc is recoverable from the COPY layer).`

## PoC-Test Recipes — Iron Law Discipline

Every W5 control ships with a failing-then-passing PoC test. The recipes below cover the two tools the user-community uses most for OCI-image testing: `container-structure-test` (for runtime-state assertions on the final image) and `dive` (for layer-level extraction tests, the only tool that catches W5-12).

### Recipe A — container-structure-test (runtime-state assertions)

`container-structure-test` runs YAML-driven assertions against a built image without launching the application. Configured per project, runs in CI as a required check.

```yaml
# tests/container/structure-test.yaml
schemaVersion: '2.0.0'

commandTests:
  # W5-4: non-root enforcement (UID >= 1000)
  - name: 'runs as non-root UID >= 1000'
    command: 'id'
    args: ['-u']
    expectedOutput: ['^[1-9][0-9]{3,}$']

  # W5-1: builder toolchains absent in final image
  - name: 'no npm in final image'
    command: 'sh'
    args: ['-c', 'command -v npm 2>/dev/null || echo absent']
    expectedOutput: ['^absent$']
  - name: 'no gcc in final image'
    command: 'sh'
    args: ['-c', 'command -v gcc 2>/dev/null || echo absent']
    expectedOutput: ['^absent$']

fileExistenceTests:
  # W5-2: secrets-dragging .env not in image
  - name: '.env not present in /app'
    path: '/app/.env'
    shouldExist: false
  - name: '.git not present in /app'
    path: '/app/.git'
    shouldExist: false

metadataTest:
  # W5-5: USER is numeric (not a name)
  user: '10001'
  # W5-10/11: ENV does not contain known secret patterns (regex-checked separately by Recipe B)
```

Three rules:
1. **Run on every CI build.** Required check on the merge gate; non-zero exit blocks the merge.
2. **Pin the test-tool version.** `container-structure-test` versions are pinned in CI; floating-`latest` here defeats the purpose of pinning the image itself (W5-7).
3. **Pair structure-tests with dive scans (Recipe B).** Structure-tests cover the *final* filesystem; dive covers *every layer*. Both are required — W5-12 is invisible to structure-tests by construction.

### Recipe B — dive (layer-level extraction and secret-pattern scan)

`dive` exposes per-layer filesystem deltas. Used in CI mode (`dive --ci`), it can fail builds on layer-level metric thresholds — including detection of secret-pattern files in any layer, not just the final state.

```bash
#!/usr/bin/env bash
# tests/container/dive-scan.sh — runs in CI, gated as a required check.

set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref>}"
SECRETS_REGEX='AKIA[0-9A-Z]{16}|sk_live_[a-zA-Z0-9]{24,}|ghp_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9_-]{20}|-----BEGIN [A-Z]+ PRIVATE KEY-----'

# 1. Layer-level efficiency check (catches W5-12 — wasted space from COPY+rm patterns is a strong signal)
dive --ci --lowestEfficiency 0.95 --highestUserWastedPercent 0.05 "$IMAGE"

# 2. Secret-pattern scan across every layer's filesystem snapshot
TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT
docker save "$IMAGE" -o "$TMP/image.tar"
tar -xf "$TMP/image.tar" -C "$TMP"

# Each layer is a tar.gz blob under blobs/sha256/<digest>; non-layer blobs (config, manifest) are skipped.
for layer in "$TMP"/blobs/sha256/*; do
  if file "$layer" | grep -qE 'gzip compressed|POSIX tar archive'; then
    if tar -xzOf "$layer" 2>/dev/null | grep -aoE "$SECRETS_REGEX" | head -1 | grep -q .; then
      echo "FAIL W5-D: secret pattern matched in layer $(basename "$layer")" >&2
      exit 1
    fi
  fi
done

echo "OK: dive layer scan passed; no secret patterns in any layer."
```

Three rules:
1. **Scan every layer, not just the final filesystem.** W5-12 (COPY then rm) is invisible to a final-filesystem scan; layer-level inspection is the only way to catch it. A scanner that reports "image clean" without iterating layers is a W0-13-shaped false sense of security at the W5 layer.
2. **Use `dive --ci` thresholds with care.** `--lowestEfficiency 0.95` catches gross waste; tune per project. `--highestUserWastedPercent 0.05` flags COPY-then-rm patterns specifically — wasted space is a proxy for "data was copied in and removed in a later layer," which is exactly the W5-12 signal.
3. **Run on the post-build, pre-push image.** A scan that runs after registry push is too late — the leaked layer is already published and any consumer with prior pull access has it cached. Pre-push gating is the only effective enforcement.

## Image Provenance Verification Checklist

The W5 analogue of W0's Bypass-Resistance checklist. A repo passes provenance only when **every** box is checked.

- [ ] **All `FROM` directives are digest-pinned** (W5-7). `grep -E '^FROM\s+\S+:[^@]+\s*$' Dockerfile*` returns empty.
- [ ] **Every published image is signed with cosign** (W5-9). `cosign verify --certificate-identity-regexp <regex> <image>` succeeds.
- [ ] **Every published image has an SBOM attestation** (W5-8). `cosign tree <image>` shows a CycloneDX or SPDX attestation.
- [ ] **Every published image has a SLSA provenance attestation** (W5-8). `cosign tree <image>` shows a `https://slsa.dev/provenance/v1` attestation.
- [ ] **Build runs in an ephemeral, isolated builder** (W5-3). No shared cache surface across tenants on the same builder; cache mounts are scoped per project.
- [ ] **Build secrets enter via `--mount=type=secret`, never `--build-arg` or `ENV`** (W5-10, W5-11). `grep -E '^(ARG|ENV) (NPM_TOKEN|API_KEY|.*SECRET|.*PASSWORD|GITHUB_TOKEN)' Dockerfile*` returns empty.
- [ ] **Final stage is a minimal base** (W5-1). `docker history <image>` shows no package-manager invocations in the final-stage layer set.
- [ ] **`USER` is numeric and >= 1000** (W5-4, W5-5). `docker inspect --format='{{.Config.User}}' <image>` matches `^[0-9]{4,}(:[0-9]{4,})?$`.
- [ ] **`.dockerignore` excludes `.env*`, `.git/`, `node_modules/`, `*.pem`, `secrets/`** (W5-2).
- [ ] **`dive --ci` and `container-structure-test` run as required CI checks** (Recipes A + B).
- [ ] **Layer-level secret-pattern scan runs on every build** (Recipe B). The scan iterates every blob; final-filesystem-only scans do not satisfy this box (W5-12).
- [ ] **The W5 posture is documented in `<project>/.security-pilot/PROJECT_PILOT.md`** — registry, signing identity, base-image policy, SBOM consumer, last full-image scan date.

A repo passes provenance verification only when **every** box is checked. A partially-checked posture is a finding, not a state.

## Finding template (use exactly this structure)

```markdown
### W5-<n> — <one-line title>

**Severity:** Critical | High | Medium | Low | Info  *(definitions in PILOT.md)*
**Maps to:** OWASP A0X · ASVS V0X.X · CWE-XX · CIS Docker Y.Z · NIST SP 800-190 §X.Y · W5-<row-id>
**File / artifact:** `Dockerfile:LINE` (or `<image-ref>@<digest>`)
**Status:** open

**Vulnerability**
What is wrong, in one paragraph. Cite the specific construct and why it violates the cited standards.

**Real-world impact**
A real incident, post-mortem, advisory, or industry-benchmark report demonstrating this defect's exploitation. Per the project's Contributing rule, every footgun row cites at least one credible primary or industry source.

**Remediation strategy**
Wave: W5  *(this skill)*
The fix shape, plus the provenance-verification step that gates re-occurrence (which checklist box this finding maps to).

**Verification test**
Failing test that gates the fix (Iron Law PoC). One-line description here; full test code lives in `tests/container/`.
```

## Anti-patterns this skill rejects

- A finding without a citation across at least one of OWASP / ASVS / CWE / CIS Docker / NIST SP 800-190.
- "We use Alpine, so we're fine" — Alpine is not an audit conclusion (CVE-2019-5021 demonstrated alpine root password defaults can drift across releases). Apply the full W5 checklist regardless of base.
- Final-stage cleanup via `RUN rm` of a previously-COPY'd secret (W5-12). The cleanup is theatre; layer extraction defeats it.
- Treating `--build-arg` as a secrets mechanism (W5-11). Use `--mount=type=secret`.
- Pinning by tag alone (W5-7). The tag is documentation; the digest is enforcement.
- Reverting non-root USER to root because "permissions issues" (W5-6). Pre-create and `chown` the directories.
- Skipping SBOM emission because "it's a private image" (W5-8). Private images still need post-incident debuggability — Log4Shell didn't care whose registry the image lived in.
- Trusting the registry without signature verification (W5-9). Cosign is one CI step; absence is a finding even if the registry is internal.
- Final-filesystem-only secret scans declared as W5-D coverage (W5-12). Layer-level scan is non-negotiable.

## TODO before this skill is cut from `3.1.0-alpha` to non-alpha `3.1`

1. **Citation review.** CVE-2024-21626 ("leaky vessels", runC), CVE-2021-32638 (Codecov bash uploader), CVE-2021-44228 (Log4Shell, cited for SBOM-response motivation), CVE-2019-5021 (Alpine root password) need primary-source links from NVD / vendor advisories before this file goes GA. The npm CVE-2022-29244 reference in W5-1 also needs verification.
2. **Validation on a reference image.** All 12 PoC-test recipes need to run end-to-end against a fresh test image, in CI, with both successful (passing assertion) and failing (negative-case) Dockerfiles. Currently structurally drafted only.
3. **Multi-arch and non-Dockerfile adapter notes.** This draft assumes Dockerfile-based builds. Buildpacks (`pack build`), `ko` (Go), `Jib` (Java), and nixpacks generate images differently and need their own adapter sections — `ko` for example produces digest-pinned images by default but does not run a `USER` directive without explicit config; Buildpacks do most of W5-1 / W5-4 for free but make W5-7 (digest pinning of the builder itself) more important.
4. **Severity calibration review.** ✓ Assigned in v3.1-alpha. Distribution: **1 Critical** (W5-12) — the silent-killer layer-extraction case; **6 High** (W5-1, W5-2, W5-3, W5-6, W5-10, W5-11) — direct exposure or active enforcement-regression classes; **5 Medium** (W5-4, W5-5, W5-7, W5-8, W5-9) — defense-in-depth and provenance-gap rows. Re-review at non-alpha cut against any post-validation findings; W5-10 (ENV with secret) flips to Critical on public registries.
5. **Cross-reference into `framework-footguns.md`.** The cosign / SBOM / Buildpack / `ko` rows want sibling entries in the framework footgun library so application-layer audits can cross-cite.
6. **W6 dependency map.** Document which W5 findings, if unfixed, prevent W6 audits from being meaningful — e.g., NetworkPolicy default-deny on a root-running image still leaves a much wider blast radius than on a non-root image; an unsigned image (W5-9) makes admission-policy enforcement (W6) decoration unless the policy verifies the signature.
7. **Cut canonical pilot from `3.1.0-alpha` to `3.1`** once items 1–6 are complete and reviewed.
