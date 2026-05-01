# sec-container — Wave 5: Container / OCI Image Hardening

> **STATUS: v3.1 SCAFFOLDING STUB.** This skill is not operational. Do not invoke `/sec-container` against a project until this file is filled in and the canonical pilot version is cut from `3.1.0-alpha` to a non-alpha `3.1`. Until then, the pilot operates under v3.0 (W1–W4) only.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 5 audits the **build artifact** — the OCI image produced by the project's Dockerfile (or Buildpack, ko, Jib, nixpacks, etc.). It runs after W1–W4 (application-layer fixes) and before W6 (orchestration). The image is the unit of deployment; an image that runs as root, pulls a `:latest` base, or carries build-time toolchains into the runtime stage is an attack surface no orchestration policy can fully mitigate.

W5 depends on W0 being satisfied: a Dockerfile committed without W0 lint may have already shipped a bad pattern.

## What this skill will produce *(when filled in)*

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-container.md` with:

- Per-image findings (one section per Dockerfile / build target).
- Each finding cites OWASP / ASVS / CWE / CIS Docker Benchmark / NIST SP 800-190 IDs as appropriate.
- A remediation order within W5 by blast radius descending: root-running images > unpinned base > toolchain-in-runtime > missing healthchecks > metadata gaps.
- Iron Law–compliant fixes: every W5 patch ships with a failing PoC test (e.g., container-structure-test, dive layer-budget assertion, runtime `id` check) that proves the bad state, then passes after the fix.

## Scope (when active)

- **Non-root enforcement.** `USER` directive set to a non-zero UID/GID; verified via runtime check, not just Dockerfile grep. CWE-250 / CIS 4.1.
- **Multi-stage build hardening.** Build toolchains, package managers, and source code do not survive into the final stage. Final stage uses a minimal base (distroless, scratch, alpine where the runtime allows).
- **Base-image pinning by digest.** `FROM image@sha256:…` not `FROM image:tag`. Tag mutation is a documented supply-chain attack vector. CWE-1357.
- **Layer-cache hygiene.** Secrets never appear in any intermediate layer (build-args alone are insufficient; `--mount=type=secret` or external KMS injection is required). CWE-538.
- **Capability minimization.** No `--privileged`, no unnecessary Linux capabilities; document the *minimum* set required and pin it.
- **Healthcheck and signal handling.** PID 1 reaps zombies (`tini` / `dumb-init` or proper init); `STOPSIGNAL` matches the runtime's expectation; `HEALTHCHECK` defined or explicitly delegated to orchestrator.
- **SBOM and provenance.** Image carries an SBOM (CycloneDX or SPDX) and SLSA provenance attestation; CI verifies on pull.

## Out of scope

- Runtime network policy (that is W6 — orchestration).
- Application-layer vulnerabilities inside the image (those are W1–W4; the image is just their delivery vehicle).
- Image-registry access control (that is an infrastructure / W0 gating concern).

## Iron Law applies recursively

Every Wave 5 control must ship with a failing PoC test that proves the bad state would have shipped, then passes after the fix. A claim that "the image runs as non-root" without a `docker run --rm <image> id -u` assertion in CI is not an enforced control — it is a comment.

## TODO before this skill goes operational

1. Citation map: OWASP / ASVS / CWE / CIS Docker Benchmark / NIST SP 800-190 row IDs for each footgun row.
2. Footgun catalogue for the seven scope items above, with anti-pattern Dockerfile snippets and canonical fixes — using the same authoring conventions as `PILOT.md` §"Authoring Conventions" (placeholders for hook-trigger substrings).
3. PoC-test recipes: container-structure-test config, dive layer-budget thresholds, runtime `id`/cap assertion templates.
4. Buildpack / ko / Jib / nixpacks adapter notes — these tools generate Dockerfiles or images directly and have different failure modes than hand-written Dockerfiles.
5. Registry-side verification recipe (cosign signature + SLSA provenance verification on pull).
6. Cut canonical pilot from `3.1.0-alpha` to `3.1` once items 1–5 are filled in and reviewed.
