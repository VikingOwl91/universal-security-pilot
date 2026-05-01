# sec-orchestration — Wave 6: Kubernetes / Orchestration Hardening

> **STATUS: v3.1 SCAFFOLDING STUB.** This skill is not operational. Do not invoke `/sec-orchestration` against a project until this file is filled in and the canonical pilot version is cut from `3.1.0-alpha` to a non-alpha `3.1`. Until then, the pilot operates under v3.0 (W1–W4) only.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 6 audits the **runtime layer** — the Kubernetes manifests, Helm values, Kustomize overlays, or equivalent orchestration descriptors that govern how the W5 image actually runs in production. It is the outermost wave: W1–W4 fix the application, W5 hardens the artifact, W6 constrains how the artifact is permitted to behave once running.

W6 depends on W5 being satisfied: an orchestration policy applied to an image that itself runs as root has a much larger residual blast radius than the same policy applied to a non-root image.

## What this skill will produce *(when filled in)*

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-orchestration.md` with:

- Per-workload findings (one section per Deployment / StatefulSet / DaemonSet / CronJob).
- Each finding cites OWASP / ASVS / CWE / CIS Kubernetes Benchmark / NIST SP 800-190 / NSA-CISA Kubernetes Hardening Guide IDs as appropriate.
- A remediation order within W6 by blast radius descending: cluster-admin RBAC > plaintext secrets > missing NetworkPolicy > missing PodSecurity > missing resource limits > missing probes.
- Iron Law–compliant fixes: every W6 patch ships with a failing PoC test (kind/k3d cluster + `kubectl apply` + assertion) that proves the bad state, then passes after the fix.

## Scope (when active)

- **RBAC least-privilege.** No `cluster-admin` for workload ServiceAccounts; per-namespace Roles with explicit verbs/resources; no wildcard `*` in `verbs` or `resources` outside platform-team-owned controllers. CWE-269 / CIS 5.1.
- **Secret handling.** No plaintext secrets in YAML committed to git. External Secrets Operator, Sealed Secrets, SOPS, or cloud-native equivalent (AWS Secrets Manager CSI driver, Vault Agent Injector) — pick one and pin it. CWE-798.
- **NetworkPolicy default-deny.** Every namespace has an explicit default-deny ingress + egress NetworkPolicy; per-workload allow-rules opt in to specific peers. Without this, every pod can reach every other pod. CWE-923.
- **PodSecurity admission.** `restricted` profile enforced at the namespace level; deviations documented per workload with explicit justification.
- **Resource limits and requests.** Every container has both `requests` and `limits` for CPU and memory; missing limits enable noisy-neighbor DoS. CWE-400.
- **Liveness, readiness, and startup probes.** Defined per workload; missing probes hide degraded states from the scheduler and let traffic land on broken pods.
- **Image pull policy and provenance.** `imagePullPolicy: Always` for `:latest`-style tags is not a substitute for digest pinning (use digest pinning, see W5); admission controller (Kyverno, OPA Gatekeeper, sigstore policy-controller) verifies cosign signatures before scheduling.
- **Helm values discipline.** No secrets in `values.yaml` committed to git; templated secret references only; CI lint that fails on plaintext-secret regex matches in any chart artifact.

## Out of scope

- The image itself (W5) — though W6 findings frequently surface W5 prerequisites that must be fixed first.
- Cluster-level platform policy (cluster admins, control-plane hardening, etcd encryption-at-rest) — this skill audits the *workload's* manifests, not the cluster's posture. A separate `sec-cluster` skill may follow in a later release.
- CNI / service-mesh-specific policy (Calico, Cilium, Istio, Linkerd) — the skill verifies that *some* default-deny NetworkPolicy is enforced, not which CNI implements it.

## Iron Law applies recursively

Every Wave 6 control must ship with a failing PoC test that proves the bad state would have been admitted, then passes after the fix. A claim that "this namespace has default-deny NetworkPolicy" without a test pod that *attempts* the disallowed connection and asserts it is blocked is not an enforced control — it is a label.

## TODO before this skill goes operational

1. Citation map: OWASP / ASVS / CWE / CIS Kubernetes Benchmark / NIST SP 800-190 / NSA-CISA Kubernetes Hardening Guide row IDs for each footgun row.
2. Footgun catalogue for the eight scope items above, with anti-pattern manifest snippets and canonical fixes.
3. PoC-test recipes using kind/k3d ephemeral clusters: NetworkPolicy probe pods, RBAC `kubectl auth can-i` matrices, PodSecurity admission rejection assertions.
4. Helm-specific recipes: `helm template | conftest test` policy gates, secret-detection on rendered manifests, values-file lint.
5. GitOps adapter notes: how Argo CD / Flux change the audit boundary (the manifest that ships is the manifest in git, not the manifest the user wrote — drift between them is itself a finding).
6. Cut canonical pilot from `3.1.0-alpha` to `3.1` once items 1–5 are filled in and reviewed.
