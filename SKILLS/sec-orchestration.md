# sec-orchestration — Wave 6: Kubernetes / Orchestration Hardening

> **STATUS: v3.1-alpha WORKING DRAFT.** Citation map, footgun catalogue (11 rows), PoC-test recipes (`polaris` + `conftest` against OPA policies, plus kind/k3d admission tests), and admission-enforcement checklist are in place. **Not yet GA** — recipes have not been validated end-to-end on a reference cluster, and several CIS-Benchmark and NIST-citation row IDs need primary-source verification. Do not invoke against production audits until the canonical pilot is cut from `3.1.0-alpha` to a non-alpha `3.1`.

**Required reading:** Load `~/.security-pilot/PILOT.md` before applying this skill. The pilot defines the role, standards stack, severity grades, canonical patterns, and Iron Law that this skill cites.

## Position in the Wave Protocol

Wave 6 audits the **runtime layer** — the Kubernetes manifests, Helm values, Kustomize overlays, or equivalent orchestration descriptors that govern how the W5 image actually runs in production. It is the outermost wave: W1–W4 fix the application, W5 hardens the artifact, W6 constrains how the artifact is permitted to behave once running.

W6 depends on W5 being satisfied: an orchestration policy applied to an image that itself runs as root (W5-4) has a much wider residual blast radius than the same policy applied to a non-root image. An admission policy that "verifies signatures" without actually requiring them at admission (W5-9) is decoration. The W5↔W6 handshake is explicit: every W6 admission control has a corresponding W5 prerequisite, and the audit reports both.

## What this skill produces

A single Markdown file under `<project>/.security-pilot/audits/<YYYY-MM-DD>-orchestration.md` with:

- The W6 audit report header (date, cluster context, namespace scope, threat model: who can `kubectl exec`, who controls admission, who can `helm install`).
- Per-finding rows using the template at the bottom of this file.
- A Wave-6 remediation order (blast-radius descending: cluster-admin RBAC > plaintext secret in YAML > missing default-deny NetworkPolicy > missing PodSecurity restricted profile > missing image-provenance admission > resource limits / probes).
- A "tests to write first" list — every W6 fix ships with a failing PoC test per the Iron Law, generally a kind/k3d ephemeral cluster + `kubectl apply` + assertion.

## When to use

- "Audit our Helm charts before we ship to production."
- Any change to RBAC, NetworkPolicy, PodSecurity admission, or image-pull policy.
- Pre-cutover from a single-tenant cluster to a multi-tenant cluster (severity calibration shifts; previously-tolerable defaults become findings).
- Post-incident review when lateral movement, exfiltration, or token misuse is suspected.
- After adopting GitOps (Argo CD, Flux) — the manifest-that-ships boundary changes; drift between rendered manifest and committed manifest is itself a W6 finding.

## When NOT to use

- A pure application-code review with no manifest change — that is W1–W4.
- A cluster-platform audit (control-plane hardening, etcd encryption-at-rest, kubelet TLS) — that is a separate `sec-cluster` skill domain (planned for a later release). W6 audits the **workload's** manifests, not the cluster's posture.
- Service-mesh-specific policy (Istio, Linkerd, Cilium policies) when no equivalent native primitive is in scope — flag the gap and defer.

## Pre-audit grounding

1. **Inventory the manifests.** Every `Deployment`, `StatefulSet`, `DaemonSet`, `CronJob`, `Job`, `Service`, `Ingress`, `NetworkPolicy`, `Role`, `RoleBinding`, `ClusterRole`, `ClusterRoleBinding`, `ServiceAccount`, `Secret`, `ConfigMap` in scope. Helm: render with `helm template <release> <chart> -f <values>` first; audit the **rendered** output, not just the templates.
2. **Identify the cluster topology.** Single-tenant vs multi-tenant. Namespace isolation strategy. Service mesh present? Admission controllers active (Pod Security Standards, Kyverno, OPA Gatekeeper, sigstore policy-controller)?
3. **Walk RBAC with `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> --list`.** Note any `*` verbs or wildcard resources. Compare each workload's effective permissions to the documented minimum.
4. **Resolve image references.** Every `image:` field must be checked: digest-pinned? signed? on the allowlisted registry? Cross-reference W5 audit results — a W5-7 finding is also a W6 finding when the cluster admits unpinned images.
5. **Confirm GitOps drift posture.** If Argo CD / Flux is active, compare the committed manifest to the live `kubectl get -o yaml` output. Drift between them is a W6 finding by itself — the manifest in git is not the manifest the cluster runs.
6. **Check W5 prerequisites.** A workload running an image that fails W5 audit cannot meaningfully pass a W6 audit; flag the W5 finding and proceed with the caveat that W6 mitigations have a wider residual blast radius until W5 is fixed.

## Citation Map — OWASP / ASVS / CWE / CIS Kubernetes Benchmark / NIST

| Category | OWASP Top 10 (2021) | OWASP ASVS L2 | CWE | CIS Kubernetes Benchmark | NIST / NSA-CISA |
|---|---|---|---|---|---|
| RBAC least-privilege | A01 Broken Access Control · A04 Insecure Design | V4.1 (general access control) · V4.2 (operation-level) · V14.2.1 | CWE-269 Improper Privilege Management · CWE-732 Incorrect Permission Assignment · CWE-250 Execution with Unnecessary Privileges | 5.1.1 (cluster-admin to least-priv) · 5.1.3 (no wildcard) · 5.1.5 (default SA tokens) · 5.1.6 (SA token automount) | NSA-CISA Kubernetes Hardening Guide §III · NIST SP 800-190 §4.6.1 |
| PodSecurity admission | A05 Security Misconfig | V14.3.2 (hardening defaults) · V14.2.1 | CWE-250 · CWE-732 · CWE-693 Protection Mechanism Failure | 5.2.1–5.2.6 (Pod Security Standards) · 5.2.4 (no privileged) · 5.2.6 (no hostNetwork) · 5.2.10 (readOnlyRootFilesystem) | NSA-CISA §IV · NIST SP 800-190 §4.4.1 / §4.4.4 |
| Secret handling | A02 Cryptographic Failures · A07 Identification & Auth Failures | V14.1.5 (no inline secrets) · V8.3.4 (sensitive data not logged) · V2.10 (token storage) | CWE-798 Use of Hardcoded Credentials · CWE-540 Inclusion of Sensitive Information · CWE-522 Insufficiently Protected Credentials · CWE-312 Cleartext Storage | 5.4.1 (Secret as files, not env) · 5.4.2 (no plaintext in manifests) | NSA-CISA §V · NIST SP 800-190 §4.5.5 |
| NetworkPolicy default-deny | A05 · A04 | V13.1.1 (network segmentation) · V13.1.5 | CWE-923 Improper Restriction of Communication Channel · CWE-693 · CWE-862 Missing Authorization | 5.3.2 (CNI supports NetworkPolicy) · 5.3.3 (default-deny applied per namespace) | NSA-CISA §VI · NIST SP 800-190 §4.6.4 |
| Image provenance at admission | A05 · A06 Vulnerable Components · A08 Software & Data Integrity Failures | V10.3.2 (data integrity) · V14.2.1 | CWE-1357 · CWE-353 Missing Support for Integrity Check · CWE-345 Insufficient Verification of Authenticity | 5.5.1 (image provenance) · 5.7 (admission control) | NSA-CISA §IV (registry / admission) · NIST SP 800-190 §4.5.1 |

Standard citation line:
```
**Maps to:** OWASP A01 · ASVS V4.1.5 · CWE-269 · CIS K8s 5.1.3 · NSA-CISA §III · W6-2
```

## Footgun Catalogue — Wave 6

Each row uses the framework-footguns block format: **Severity · Maps to · Symptom · Why wrong · Canonical fix · PoC test shape.**

### Category W6-A — RBAC Least-Privilege

#### W6-1 — Workload `ServiceAccount` bound to `cluster-admin`
**Severity:** Critical  *(full cluster compromise on workload compromise; no preconditions beyond pod takeover)*
**Maps to:** OWASP A01 · A04 · ASVS V4.1.1 · V4.2.1 · CWE-269 · CWE-250 · CIS K8s 5.1.1 · NSA-CISA §III
**Symptom in code:** A `ClusterRoleBinding` or `RoleBinding` whose `roleRef` is `cluster-admin` (or any `ClusterRole` aggregating `cluster-admin` rules) and whose `subjects[].kind` is `ServiceAccount` for a workload — not a platform admin or cluster-operator identity.
**Why it's wrong:** A workload's ServiceAccount token is automatically mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token` and is reachable by any process inside the pod, including any RCE the application might be vulnerable to. Binding that SA to `cluster-admin` means a single application-layer compromise (W1–W4 finding) escalates to full cluster takeover — every namespace, every secret, every workload, every node. The pattern recurs because dev clusters tolerate it for convenience and the binding survives the dev-to-prod migration. CIS K8s 5.1.1 is unambiguous: cluster-admin is reserved for human cluster operators, never workload identities.
**Canonical fix:** (a) Replace the binding with a workload-specific `Role` granting only the verbs and resources the workload genuinely needs (`get`/`list` on the specific ConfigMaps and Secrets it reads, `create` on the specific CRDs it produces); (b) `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> '*' '*'` returns "no" — this is the audit gate; (c) the documented minimum is captured in the Helm chart / Kustomize overlay so it's reviewable; (d) periodic RBAC review compares effective permissions to documented minimum.
**PoC test shape:** `Test: kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> '*' '*' returns "no"; the same query against a workload bound to cluster-admin returns "yes" and is the failing case.`

#### W6-2 — Wildcard `verbs` or `resources` in a `Role` / `ClusterRole`
**Severity:** Critical  *(broad permission blanket; every CRD added later is implicitly granted)*
**Maps to:** OWASP A01 · A04 · ASVS V4.1.5 · V4.2.2 · CWE-269 · CWE-732 · CIS K8s 5.1.3
**Symptom in code:** A `Role` or `ClusterRole` with `verbs: ["*"]` (any verb), `resources: ["*"]` (any resource), `apiGroups: ["*"]` (any API group), or any combination — outside platform-team-owned controllers (cluster-autoscaler, ingress controllers, CSI drivers).
**Why it's wrong:** Wildcard permissions are forward-incompatible by design: every new CRD installed later (Argo CD Application, Cert-Manager Certificate, External Secrets Operator ExternalSecret, Velero Backup) is implicitly granted to the holder. A workload SA with `verbs: ["*"]` on `resources: ["*"]` for `apiGroups: [""]` can read every Secret in its namespace today and every Secret-shaped CRD installed tomorrow. The wildcard pattern also defeats RBAC review: `kubectl describe role` reports literally `*`, which tells the reviewer nothing about effective scope. Explicit verbs (`get`, `list`, `watch`, `create`, `update`, `patch`, `delete`) and explicit resource lists make the permission auditable; wildcards make it opaque.
**Canonical fix:** (a) Enumerate verbs explicitly — `verbs: ["get", "list", "watch"]` for read-only consumers; never `["*"]`; (b) enumerate resources explicitly — `resources: ["configmaps", "secrets"]` with `resourceNames: ["<specific-cm>"]` where the workload reads only one; (c) split read-side and write-side into separate Roles so the principle of least privilege is auditable per call-site; (d) policy-as-code (Kyverno or OPA Gatekeeper) rejects any new Role or ClusterRole with wildcard verbs or resources at admission time.
**PoC test shape:** `Test: kubectl create -f <role-with-wildcard-verbs.yaml> is rejected by the Kyverno/Gatekeeper policy with a structured error referencing the wildcard rule; the same Role with explicit verbs is accepted.`

#### W6-3 — Default `ServiceAccount` used by workload (or `automountServiceAccountToken: true` without explicit need)
**Severity:** Medium  *(unnecessary credential exposure; widens the SA-token attack surface)*
**Maps to:** OWASP A01 · A05 · ASVS V4.1.3 · CWE-272 Least Privilege Violation · CIS K8s 5.1.5 · 5.1.6
**Symptom in code:** A workload manifest that does not specify `spec.serviceAccountName` (so the namespace's `default` SA is used), or specifies one but does not set `automountServiceAccountToken: false` when the workload makes no Kubernetes API calls.
**Why it's wrong:** Every namespace has a `default` ServiceAccount. Workloads that don't need to talk to the Kubernetes API still inherit it, *and* the SA token is auto-mounted at the documented path inside the pod. An RCE in such a workload now has a Kubernetes API token it has no business possessing — even if the default SA has minimal RBAC, the existence of the token at a known path is a stepping stone for token-theft and lateral-movement tooling. The fix is two lines per workload manifest. The pattern recurs because `serviceAccountName` is optional and the auto-mount default is `true`, both designed for convenience over security.
**Canonical fix:** (a) Every workload sets `spec.serviceAccountName` to a workload-specific SA (named after the workload); (b) workloads that do not call the Kubernetes API set `automountServiceAccountToken: false` at the pod-spec level (or on the SA itself); (c) the default SA in each namespace has zero RBAC bindings — even cluster-admin namespaces; (d) Kyverno/Gatekeeper policy rejects workloads that omit `serviceAccountName` or that auto-mount tokens without a documented exception.
**PoC test shape:** `Test: kubectl apply -f <pod-without-serviceAccountName.yaml> is rejected by admission; a pod with serviceAccountName set and automountServiceAccountToken: false (when no API access is needed) is accepted.`

### Category W6-B — PodSecurity Admission

#### W6-4 — Pod runs as root (no `runAsNonRoot: true` enforcement)
**Severity:** High  *(W5-4 finding becomes runtime-effective; container-escape blast radius unbounded)*
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-250 · CWE-269 · CIS K8s 5.2.4 · 5.2.6 · NSA-CISA §IV
**Symptom in code:** Pod spec without `securityContext.runAsNonRoot: true` and `securityContext.runAsUser: <non-zero>`; namespace not labeled with PodSecurity admission `pod-security.kubernetes.io/enforce: restricted` (or equivalent baseline / restricted profile).
**Why it's wrong:** This is the W5↔W6 handshake. W5-4 (no `USER` in the Dockerfile) ships an image that runs as root by default; W6-4 fails to constrain that at admission. Combined, the workload runs as UID 0 with full Linux capabilities. CVE-2024-21626 ("leaky vessels", runC <1.1.12) demonstrated that container-escape from root is feasible; the same exploit attempt from a non-root user fails. PodSecurity admission's `restricted` profile rejects pods that don't set `runAsNonRoot: true` — the protection exists, it just has to be enabled at the namespace level. NSA-CISA Kubernetes Hardening Guide §IV is explicit on this.
**Canonical fix:** (a) Every workload manifest sets `spec.securityContext.runAsNonRoot: true` and `spec.securityContext.runAsUser: 10001` (mirroring the W5 USER directive); (b) every namespace is labeled with `pod-security.kubernetes.io/enforce: restricted` (the strictest profile) or `baseline` with documented exceptions; (c) admission rejects pods that don't satisfy the profile — `enforce`, not `audit` or `warn`; (d) the W5 USER UID and W6 `runAsUser` value are documented identically in `PROJECT_PILOT.md` so cross-layer consistency is auditable.
**PoC test shape:** `Test: kubectl apply on a pod without runAsNonRoot in a namespace labeled pod-security.kubernetes.io/enforce: restricted is rejected with "forbidden: violates PodSecurity restricted"; the same pod with runAsNonRoot: true and runAsUser: 10001 is accepted.`

#### W6-5 — Writable root filesystem (no `readOnlyRootFilesystem: true`)
**Severity:** Medium  *(persistent compromise foothold; defense-in-depth gap)*
**Maps to:** OWASP A05 · ASVS V14.3.2 · CWE-732 · CWE-693 · CIS K8s 5.2.10 · NSA-CISA §IV
**Symptom in code:** Pod spec containers without `securityContext.readOnlyRootFilesystem: true`; or with the flag set but no `emptyDir` volumes mounted at the writable paths the app actually needs (so the team would revert the flag the moment the app crashes).
**Why it's wrong:** A writable container root filesystem allows any RCE to drop persistence (cron entries, modified shell rc files, library substitution, kubectl-shaped binaries staged for later use). With `readOnlyRootFilesystem: true`, the attacker can only write to explicitly-mounted writable volumes — typically `/tmp`, `/var/run`, and any `emptyDir` the workload declared. This shrinks the persistence surface dramatically. The pattern of *not* setting it persists because the immediate developer experience is "container won't start" when the app writes to a path that's now read-only; the fix is to enumerate and mount the genuine write paths, not to revert the flag.
**Canonical fix:** (a) `securityContext.readOnlyRootFilesystem: true` on every container spec; (b) `volumeMounts` with `emptyDir` volumes for each genuine write path (`/tmp`, `/var/run/<app>`, `/var/log/<app>`); (c) the app's writable paths are documented in `PROJECT_PILOT.md` so future maintainers don't add a path under `/etc/` or `/usr/` and "fix" the resulting failure by reverting the flag; (d) PodSecurity `restricted` does NOT mandate this flag, so it requires an explicit Kyverno/Gatekeeper policy to enforce.
**PoC test shape:** `Test: kubectl exec into the pod and run "touch /tmp/x && touch /etc/x" — the first succeeds, the second fails with "Read-only file system"; a pod without readOnlyRootFilesystem: true allows both, which is the failing case.`

### Category W6-C — Secret Handling

#### W6-6 — Plaintext secret in committed `values.yaml` or YAML manifest
**Severity:** Critical  *(direct credential exposure; visible to every git reader; rotation requires republish)*
**Maps to:** OWASP A02 · A07 · ASVS V14.1.5 · V8.3.4 · CWE-798 · CWE-312 · CWE-540 · CIS K8s 5.4.2 · NSA-CISA §V
**Symptom in code:** A `values.yaml`, `values-prod.yaml`, chart-bundled `secrets.yaml`, or raw `Secret` manifest containing literal passwords, API tokens, or signing keys (`stringData: { password: "actualPassword" }` or `data: { password: "<base64-not-encryption>" }`). Note: base64 in a `Secret`'s `data:` field is not encryption — it's encoding. CIS K8s 5.4.2 is explicit on this.
**Why it's wrong:** Helm renders these into `Secret` manifests at install time. The plaintext sits in git, in the rendered manifest, in `helm get values`, and (depending on history retention) in every cluster snapshot. This is the W6 analogue of W0-4's pre-commit lint. The defect compounds when the chart is published to a chart registry — the secret is now in *every* chart consumer's clone. Rotation requires republishing the chart, updating every consumer's pin, and reinstalling — and every prior install of the previous chart version still has the old credential.
**Canonical fix:** (a) Charts reference an external secret store via templated lookups — `External Secrets Operator` (ExternalSecret / SecretStore CRDs), `Sealed Secrets` (encrypted at rest, decrypted by the controller), `SOPS` with age/PGP/KMS, or cloud-native CSI drivers (`secrets-store.csi.x-k8s.io` for AWS Secrets Manager / Azure Key Vault / GCP Secret Manager); (b) the chart's `values.yaml` contains *references* to secrets, never the secret values themselves; (c) CI lint that fails on plaintext-secret regex matches in any chart artifact (`helm template <chart> | gitleaks detect --no-git`); (d) the W0 audit (`/sec-precommit`) catches it pre-commit; W6 catches it as a defense-in-depth backstop.
**PoC test shape:** `Test: helm template <chart> -f <values> | grep -E '^\s*(password|token|secret|apiKey).*: [^${}].+$' returns empty; the same chart with literal "password: hunter2" in values fails the assertion.`

#### W6-7 — Secret mounted via env var instead of volume
**Severity:** Medium  *(visibility via `kubectl describe pod` and process environment; broader audience)*
**Maps to:** OWASP A02 · A09 Logging & Monitoring · ASVS V8.3.4 · CWE-540 · CWE-200 · CIS K8s 5.4.1
**Symptom in code:** Pod spec uses `env: [{ name: DB_PASSWORD, valueFrom: { secretKeyRef: ... } }]` to inject a secret as an environment variable, rather than mounting it via `volumes: [{ secret: ... }]` and `volumeMounts: [{ mountPath: /etc/secrets/... }]`.
**Why it's wrong:** Environment variables are visible to every process in the pod via `/proc/<pid>/environ`, surface in crash dumps, often surface in error-reporting payloads (`process.env` snapshots in Node, `os.environ` dumps in Python tracebacks), and appear in `kubectl describe pod <pod>` output (which is readable by anyone with `pods/describe` RBAC — typically a much wider audience than `secrets/get`). File-mounted secrets, by contrast, are restricted by Linux file permissions and don't leak through environment-snapshotting code paths. CIS K8s 5.4.1 specifies file-mount for this reason.
**Canonical fix:** (a) Secrets enter the pod as files under `/etc/secrets/<name>` via `volumes:` + `volumeMounts:`; (b) the application reads the file at startup (or watches it for rotation), never via `process.env` / `os.environ`; (c) the file mount uses `defaultMode: 0400` so only the workload's UID can read it; (d) when env-var injection is genuinely required (some legacy frameworks demand it), document the exception in `PROJECT_PILOT.md` with a justification line.
**PoC test shape:** `Test: kubectl describe pod <pod> | grep -A2 "DB_PASSWORD" shows "<set to the key 'password' in secret '...'>" rather than the literal value (file mount); a workload using env: valueFrom: secretKeyRef shows the *reference* but the running process's /proc/1/environ still contains the value, which the assertion specifically forbids.`

### Category W6-D — NetworkPolicy Default-Deny

#### W6-8 — Namespace without default-deny **ingress** NetworkPolicy
**Severity:** High  *(every pod reaches every other pod by default; lateral movement unconstrained)*
**Maps to:** OWASP A05 · A04 · ASVS V13.1.1 · V13.1.5 · CWE-923 · CWE-862 · CIS K8s 5.3.3 · NSA-CISA §VI
**Symptom in code:** A namespace with workloads but no `NetworkPolicy` resource that selects all pods (`podSelector: {}`) and denies all ingress (`policyTypes: ["Ingress"]`, no `ingress:` rules); per-workload allow-rules exist but no underlying default-deny.
**Why it's wrong:** Without a default-deny ingress NetworkPolicy, every pod in the namespace is reachable from every other pod in *every* namespace (cluster-wide, by default). A compromise of any application — including a third-party admin panel, a debugging tool deployed to a "dev" namespace — pivots to every other workload's listening port. Per-workload allow-policies are necessary but not sufficient: in NetworkPolicy semantics, the absence of any policy selecting a pod means "allow all"; only when at least one policy selects a pod does deny-by-default apply *for that pod's policy types*. Without a default-deny baseline at the namespace level, lateral movement is the cluster's default behavior.
**Canonical fix:** (a) Every namespace has a `NetworkPolicy` named `default-deny-ingress` with `podSelector: {}` and `policyTypes: ["Ingress"]` (no rules — denies all ingress); (b) per-workload allow-policies opt back in to specific peers (`from: [{ podSelector: { matchLabels: { app: api } } }]`); (c) the CNI in use supports NetworkPolicy (Calico, Cilium, kube-router — flannel does not, by itself); (d) `kubectl get networkpolicies -A | grep default-deny-ingress` returns one entry per namespace.
**PoC test shape:** `Test: in a namespace with the default-deny-ingress policy applied, a probe pod runs "wget --timeout=3 http://target-pod:8080" and fails with timeout; in a namespace without the policy, the same probe succeeds, which is the failing case.`

#### W6-9 — Namespace without default-deny **egress** NetworkPolicy (or unrestricted egress allowed)
**Severity:** High  *(exfiltration path is open; SSRF/credential-theft exploitation has nowhere to be blocked)*
**Maps to:** OWASP A05 · A10 SSRF · ASVS V13.1.5 · V12.6.1 · CWE-923 · CWE-918 · CIS K8s 5.3.3 · NSA-CISA §VI
**Symptom in code:** Namespace lacks a NetworkPolicy denying egress by default; or a workload's NetworkPolicy allows `egress: [{ to: [], ports: [...] }]` (empty `to` matches everything); or the policy permits egress to `0.0.0.0/0` for ports 80/443 with no further constraints.
**Why it's wrong:** Egress is the exfiltration path. A compromised workload with unconstrained egress can reach the cluster's internal services (every cluster IP, every node IP, `kubernetes.default.svc`), the cloud metadata endpoint (`169.254.169.254` / `fd00:ec2::254`), arbitrary internet hosts, and DNS — meaning an attacker can establish a C2 channel via DNS even when "only HTTPS" is permitted at L7. SSRF (W2-class) becomes meaningfully exploitable only when the workload can actually reach the SSRF target; default-deny egress closes that path at L4. Default-deny ingress (W6-8) prevents lateral movement *into* the workload; default-deny egress prevents data leaving *out of* the workload. Both are required. Egress is more often missed because many CNIs default to deny-ingress-only patterns.
**Canonical fix:** (a) Every namespace has a `NetworkPolicy` named `default-deny-egress` with `podSelector: {}` and `policyTypes: ["Egress"]` (no `egress:` rules); (b) per-workload allow-policies opt back in to *specific* destinations — DNS (`port: 53` to `kube-dns` only), the API server (`port: 443` to `kubernetes.default.svc` only when the workload genuinely needs it), explicit CIDRs for external dependencies; (c) external dependencies are DNS-allowlisted via Cilium FQDN policies or an egress proxy that enforces the allowlist (the L4 NetworkPolicy alone can't constrain by hostname); (d) cloud metadata endpoints are explicitly blocked via NetworkPolicy `except:` clauses or via a CNI feature that knows about them.
**PoC test shape:** `Test: a probe pod in a namespace with default-deny-egress runs "wget --timeout=3 https://example.com" and fails with timeout; the same probe with a per-workload egress allow-rule for example.com succeeds; an additional probe to 169.254.169.254 fails regardless (metadata block).`

### Category W6-E — Image Provenance Enforcement at Admission

#### W6-10 — Admission policy does not verify cosign signature on pulled images
**Severity:** High  *(W5-9 publishing-side discipline becomes runtime-meaningful only when admission verifies)*
**Maps to:** OWASP A05 · A08 · ASVS V10.3.2 · V14.2.1 · CWE-345 · CWE-353 · CIS K8s 5.5.1 · NSA-CISA §IV
**Symptom in code:** Cluster has no `sigstore policy-controller` ClusterImagePolicy, no Kyverno `verifyImages` rule, no Connaisseur configuration — or one of the above is present but in `audit` or `warn` mode rather than `enforce`; or the policy excludes the namespaces that actually run production workloads.
**Why it's wrong:** This is the W5↔W6 handshake on the provenance axis. W5-9 says "every published image is signed with cosign." W6-10 says "the cluster only admits images whose signature verifies against the expected identity." Without the admission verification, the publishing-side signing is decoration: any unsigned image (or an image signed by an unexpected identity) is admitted just the same. The OIDC-identity check is critical: a policy that verifies "any cosign signature exists" is not meaningfully stronger than no policy at all, since an attacker who can push to the registry can also sign with their own keyless identity. The policy must verify the signature against a specific Fulcio-issued certificate identity (`certificateIdentity` regex matching the team's CI OIDC subject) and a specific OIDC issuer.
**Canonical fix:** (a) Install `sigstore policy-controller` (or Kyverno with `verifyImages`); (b) define a `ClusterImagePolicy` requiring `cosign` signatures matching `certificateIdentityExpression: 'subject =~ "^https://github.com/<org>/.*@refs/heads/main$"'` and `certificateOidcIssuer: 'https://token.actions.githubusercontent.com'` (or equivalent for the team's CI provider); (c) policy applies to every namespace running workload pods (`enforce` mode); (d) audit verifies that the policy has `mode: enforce`, not `warn`/`audit`, and that no namespace exclusions silently disable it.
**PoC test shape:** `Test: kubectl apply -f <pod-with-unsigned-image.yaml> is rejected with a structured error from policy-controller referencing the missing signature; the same pod with a properly-signed image (verifiable via cosign verify) is accepted.`

#### W6-11 — Admission allows images by mutable tag (no digest pin enforcement)
**Severity:** Medium  *(complementary to W5-7; pinning is decoration without admission enforcement)*
**Maps to:** OWASP A05 · A06 · A08 · ASVS V14.2.1 · CWE-1357 · CWE-353 · CIS K8s 5.5.1
**Symptom in code:** Cluster admits pods whose `image:` field is `<repo>:<tag>` rather than `<repo>:<tag>@sha256:<digest>` (or `<repo>@sha256:<digest>`); no Kyverno/Gatekeeper policy enforces digest pinning at admission.
**Why it's wrong:** W5-7 catches unpinned `FROM` directives at the artifact-policy level. W6-11 catches unpinned `image:` references at admission. Without admission enforcement, a workload manifest can reference `acme/api:v2.4.1` and the cluster pulls whatever digest the registry currently serves under that tag — which is exactly the supply-chain risk W5-7 documents, just one layer further out. The cluster has no record of which digest was admitted yesterday vs. today. A registry compromise, mirror substitution, or DNS hijack flips the served digest under the same tag, and the cluster pulls the new content silently. Digest pinning is enforced at admission via a Kyverno policy that mutates `image:` to require the digest form, or rejects manifests where it's missing.
**Canonical fix:** (a) Kyverno policy `require-image-digest` rejects admission of any pod whose `image:` does not match `^[^@]+@sha256:[a-f0-9]{64}$`; (b) Renovate / Dependabot opens PRs to update digests, so updates are reviewable; (c) GitOps reconciliation (Argo CD / Flux) flags drift between the digest in git and the digest currently running, so silent registry-side updates can't happen even if the cluster does pull; (d) the policy is `enforce` mode; an `audit` mode is a finding by itself (W6-10 shape applies here too).
**PoC test shape:** `Test: kubectl apply -f <pod-with-tagged-image.yaml> is rejected by the require-image-digest policy; the same pod with image: <repo>@sha256:<64hex> is accepted.`

## PoC-Test Recipes — Iron Law Discipline

Every W6 control ships with a failing-then-passing PoC test. The recipes below cover the two tools the user-community uses most for Kubernetes-manifest auditing — `polaris` (preset best-practice checks) and `conftest` (OPA/Rego-based custom policies) — plus a `kind`-based ephemeral-cluster recipe for admission-time assertions that static analysis cannot make.

### Recipe A — polaris (preset best-practice checks)

`polaris` runs a default set of Kubernetes best-practice checks against rendered manifests or against a live cluster. Useful as a fast first-pass and a CI required check.

```bash
#!/usr/bin/env bash
# tests/orchestration/polaris-audit.sh — runs in CI on rendered Helm output.

set -euo pipefail

CHART="${1:?usage: $0 <chart-dir> <values-file>}"
VALUES="${2:?usage: $0 <chart-dir> <values-file>}"

# Render chart to a single YAML stream
RENDERED="$(mktemp)"
trap "rm -f '$RENDERED'" EXIT
helm template release "$CHART" -f "$VALUES" > "$RENDERED"

# Run polaris with the strict-config; fail the build on any error-severity check
polaris audit \
  --audit-path "$RENDERED" \
  --format json \
  --set-exit-code-on-danger \
  --severity danger \
  --config tests/orchestration/polaris-config.yaml
```

A sample `polaris-config.yaml` enforcing W6 controls:

```yaml
checks:
  # W6-3
  hostIPCSet: danger
  hostNetworkSet: danger
  hostPIDSet: danger
  # W6-4
  runAsRootAllowed: danger
  runAsPrivileged: danger
  notReadOnlyRootFilesystem: danger   # W6-5
  privilegeEscalationAllowed: danger
  # W6-7 (file-mounted secrets)
  hostPortSet: danger
  # W6-11
  tagNotSpecified: danger
  pullPolicyNotAlways: warning
exemptions: []
```

Three rules:
1. **Run on rendered Helm output, not raw chart templates.** The chart's templates contain `{{ .Values.* }}` placeholders; only the rendered form has the values that admission would actually see.
2. **`--set-exit-code-on-danger`** so any `danger`-severity check fails CI. Without this, polaris reports issues but exits zero — the W0-13 false-sense-of-security pattern at the W6 layer.
3. **Pin the polaris version.** Same argument as W5-7 / W0-10: a floating tool version means the gate moves under the team.

### Recipe B — conftest (OPA / Rego policies for custom enforcement)

`conftest` runs Rego policies against YAML/JSON inputs. Used for the W6 controls polaris doesn't natively cover — RBAC wildcards (W6-2), default-deny NetworkPolicy presence (W6-8 / W6-9), plaintext-secret detection (W6-6).

```rego
# tests/orchestration/policy/wave6.rego
package main

import future.keywords.in

# W6-2: wildcard verbs in Role / ClusterRole
deny contains msg if {
  input.kind in {"Role", "ClusterRole"}
  some rule in input.rules
  "*" in rule.verbs
  msg := sprintf("W6-2: wildcard verb in %v/%v", [input.kind, input.metadata.name])
}

# W6-2: wildcard resources
deny contains msg if {
  input.kind in {"Role", "ClusterRole"}
  some rule in input.rules
  "*" in rule.resources
  msg := sprintf("W6-2: wildcard resource in %v/%v", [input.kind, input.metadata.name])
}

# W6-6: plaintext secret in Helm values (heuristic: long string assigned to a secret-named key)
deny contains msg if {
  input.kind == "Secret"
  some k, v in input.stringData
  re_match("(?i)(password|token|secret|apiKey)", k)
  not startswith(v, "{{")             # not a templated reference
  count(v) > 8
  msg := sprintf("W6-6: literal-looking secret value in Secret/%v key %v", [input.metadata.name, k])
}

# W6-11: tagged image without digest pin
deny contains msg if {
  input.kind in {"Deployment", "StatefulSet", "DaemonSet", "Pod"}
  some container in object.union(
    object.get(input, ["spec", "template", "spec", "containers"], []),
    object.get(input, ["spec", "containers"], []),
  )
  not contains(container.image, "@sha256:")
  msg := sprintf("W6-11: image not digest-pinned in %v/%v container %v: %v",
                 [input.kind, input.metadata.name, container.name, container.image])
}
```

Invocation:
```bash
helm template release ./chart -f values-prod.yaml \
  | conftest test --policy tests/orchestration/policy --all-namespaces -
```

Three rules:
1. **One `deny` per finding row.** Each Rego `deny` rule maps to exactly one W6-N footgun row, so a failing test points at a specific finding ID.
2. **Run in CI as a required check.** Same gating discipline as W0 and W5: enforcement is the gate; advisory mode is theatre.
3. **Pair with admission enforcement.** A `conftest` check at CI-time catches manifests before they leave the repo; a Kyverno/Gatekeeper policy at admission-time catches manifests that bypass CI (drift, manual `kubectl apply`, GitOps reconciliation gaps). Both are required — see Recipe C.

### Recipe C — kind ephemeral cluster (admission-time assertions)

Some W6 findings are only meaningfully testable against a live cluster's admission stack — RBAC effective-permissions (W6-1), PodSecurity admission rejection (W6-4), NetworkPolicy in-cluster behavior (W6-8 / W6-9), cosign signature verification (W6-10).

```bash
#!/usr/bin/env bash
# tests/orchestration/admission-test.sh — spins up a kind cluster, applies the Helm chart, asserts admission behavior.

set -euo pipefail

CLUSTER="usp-w6-test"
trap "kind delete cluster --name '$CLUSTER' >/dev/null 2>&1 || true" EXIT

# 1. Bring up a kind cluster with PodSecurity admission preconfigured
kind create cluster --name "$CLUSTER" --config tests/orchestration/kind-config.yaml --quiet

# 2. Install Kyverno + sigstore policy-controller (or whatever the project uses)
kubectl apply -f https://github.com/kyverno/kyverno/releases/download/v1.13.1/install.yaml
kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=180s

# 3. Apply the project's W6 policies
kubectl apply -f tests/orchestration/policies/

# 4. W6-1: assert workload SA is NOT cluster-admin
kubectl auth can-i '*' '*' --as=system:serviceaccount:default:my-app
# Expected: "no". If "yes", fail.

# 5. W6-4: assert a root-running pod is rejected
if kubectl apply -f tests/orchestration/fixtures/root-pod.yaml 2>&1 | grep -q "forbidden"; then
  echo "OK W6-4: root-running pod rejected by PodSecurity"
else
  echo "FAIL W6-4: root-running pod was admitted" >&2
  exit 1
fi

# 6. W6-11: assert tagged image is rejected, digest-pinned image is accepted
if ! kubectl apply -f tests/orchestration/fixtures/tagged-image-pod.yaml 2>&1 | grep -q "denied"; then
  echo "FAIL W6-11: pod with tagged image was admitted" >&2
  exit 1
fi
kubectl apply -f tests/orchestration/fixtures/digest-pinned-pod.yaml
echo "OK W6-11: tagged image rejected, digest-pinned accepted"
```

Three rules:
1. **Use ephemeral clusters for admission tests.** Live cluster tests against a shared dev cluster create cross-test contamination; ephemeral kind/k3d clusters per CI run guarantee isolation.
2. **Pre-warm the admission stack.** Kyverno / Gatekeeper / sigstore policy-controller need their controllers up and webhooks responsive *before* the test fixtures are applied, or the tests race against admission readiness and produce flaky failures.
3. **Assert both negative AND positive cases.** A policy that rejects everything is also broken — see W0 PoC discipline.

## Admission Enforcement Checklist

The W6 analogue of W0's Bypass-Resistance and W5's Provenance-Verification checklists. A cluster passes admission enforcement only when **every** box is checked.

- [ ] **PodSecurity admission `restricted` profile enforced** at every namespace running workloads (W6-4, W6-5). `kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}{end}'` shows `restricted` (or documented `baseline` exceptions) for every workload namespace.
- [ ] **No workload SA bound to `cluster-admin`** (W6-1). `kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name == "cluster-admin") | .subjects[]?'` shows only platform-admin identities, never a workload's namespace SA.
- [ ] **No wildcard verbs or resources in workload Roles** (W6-2). `conftest` policy enforces this at CI; Kyverno/Gatekeeper enforces at admission.
- [ ] **Default ServiceAccount has zero RBAC bindings** (W6-3). `kubectl get rolebindings -A -o json | jq '.items[] | select(.subjects[]?.name == "default") | .metadata.name'` returns empty.
- [ ] **Every workload sets `serviceAccountName` and `automountServiceAccountToken: false` when no API access is needed** (W6-3).
- [ ] **No plaintext secrets in committed manifests** (W6-6). `helm template <chart> | gitleaks detect --no-git` returns clean; CI required check enforces this.
- [ ] **Every namespace has default-deny ingress NetworkPolicy** (W6-8). `kubectl get networkpolicy -A` shows one `default-deny-ingress`-named entry per workload namespace.
- [ ] **Every namespace has default-deny egress NetworkPolicy** (W6-9). Same shape, `default-deny-egress`-named.
- [ ] **Cosign signature verification enforced at admission** (W6-10). `policy-controller` or Kyverno `verifyImages` policy is in `enforce` mode, identity-pinned to the team's CI OIDC subject.
- [ ] **Image digest pinning enforced at admission** (W6-11). Kyverno `require-image-digest` policy is in `enforce` mode.
- [ ] **GitOps drift is a finding** (Argo CD / Flux). `argocd app diff <app>` returns clean for production apps; any drift is investigated, not auto-synced silently.
- [ ] **The W6 posture is documented in `<project>/.security-pilot/PROJECT_PILOT.md`** — cluster topology, admission stack, signing identity, namespace labeling strategy, last admission-test run date.

A cluster passes admission enforcement only when **every** box is checked. A partially-checked posture is a finding, not a state.

## Finding template (use exactly this structure)

```markdown
### W6-<n> — <one-line title>

**Severity:** Critical | High | Medium | Low | Info  *(definitions in PILOT.md)*
**Maps to:** OWASP A0X · ASVS V0X.X · CWE-XX · CIS K8s Y.Z.W · NSA-CISA §X · W6-<row-id>
**Manifest / resource:** `<chart>/templates/<file>.yaml:LINE` (or `<kind>/<name>` in `<namespace>`)
**Status:** open

**Vulnerability**
What is wrong, in one paragraph. Cite the specific construct and why it violates the cited standards.

**Real-world impact**
A real incident, post-mortem, advisory, or industry-benchmark report. Per the project's Contributing rule, every footgun row cites at least one credible primary or industry source.

**Remediation strategy**
Wave: W6  *(this skill)*
The fix shape, plus the admission-enforcement step that gates re-occurrence (which checklist box this finding maps to).

**Verification test**
Failing test that gates the fix (Iron Law PoC). One-line description here; full test code lives in `tests/orchestration/`.
```

## Anti-patterns this skill rejects

- A finding without a citation across at least one of OWASP / ASVS / CWE / CIS Kubernetes Benchmark / NSA-CISA Hardening Guide.
- "We're behind a VPN, so NetworkPolicy doesn't matter" — east-west traffic inside the cluster is the lateral-movement path; perimeter VPN does not constrain it (W6-8, W6-9).
- "Base64 in a Secret is encryption" (W6-6). Base64 is encoding; a `Secret`'s `data:` field is plaintext to anyone with `secrets/get` RBAC.
- Treating PodSecurity as advisory (`audit`/`warn`) rather than enforcement (W6-4, W6-5). The defect IS the absence of enforcement.
- Allowing wildcard RBAC "until we figure out the exact verbs" (W6-2). The figuring-out is the audit; the wildcard is the finding.
- Verifying signatures without identity-pinning (W6-10). "A signature exists" is not a meaningful check.
- Skipping default-deny egress because "we only have outbound traffic" (W6-9). Outbound is exactly the exfiltration path the policy exists to constrain.
- Trusting GitOps reconciliation as a substitute for admission enforcement. GitOps closes the drift gap; admission closes the bypass gap. Both are required.

## TODO before this skill is cut from `3.1.0-alpha` to non-alpha `3.1`

1. **Citation review.** CVE-2024-21626 (runC, cited indirectly via W6-4 → W5-4 handshake), the CIS Kubernetes Benchmark version pin (5.x vs current 1.x), and the NSA-CISA Kubernetes Hardening Guide section numbers all need primary-source verification before this file goes GA.
2. **Validation on a reference cluster.** All 11 PoC-test recipes (Recipes A/B/C) need to run end-to-end against a fresh `kind` cluster, with both successful and failing-case fixtures. Currently structurally drafted only.
3. **Service-mesh adapter notes.** This draft assumes native NetworkPolicy. Cilium NetworkPolicy (with FQDN egress allowlists), Istio AuthorizationPolicy, and Linkerd Server / ServerAuthorization have different semantics and need their own adapter sections — particularly for W6-9 egress (FQDN-based egress is much stronger than CIDR-only).
4. **Severity calibration review.** ✓ Assigned in v3.1-alpha. Distribution: **3 Critical** (W6-1 cluster-admin SA, W6-2 wildcard RBAC, W6-6 plaintext secret in YAML); **4 High** (W6-4 PodSecurity gap, W6-8 ingress default-deny missing, W6-9 egress default-deny missing, W6-10 no signature verification); **4 Medium** (W6-3 default SA / automount, W6-5 writable root fs, W6-7 secret-as-env, W6-11 mutable-tag admission). Re-review at non-alpha cut against any post-validation findings.
5. **Cross-reference into `framework-footguns.md`.** Helm-chart-specific patterns (values-file plaintext, `lookup` template function used to read Secrets at install time, `--set-string` history exposure) want sibling entries in the framework footgun library so chart-author audits cross-cite.
6. **W5↔W6 dependency map.** Document explicitly which W6 findings have W5 prerequisites that, if unfixed, leave the W6 control with significant residual blast radius (W6-4 ↔ W5-4, W6-10 ↔ W5-9, W6-11 ↔ W5-7). Already noted inline; want a consolidated table.
7. **Cluster-platform skill (`sec-cluster`) handoff.** Findings outside W6's scope (etcd encryption, kubelet TLS, control-plane RBAC, audit-log retention) need to defer cleanly to a future `sec-cluster` skill. Document the boundary so audits don't silently drop these — they're explicit out-of-scope, not silently-skipped.
8. **Cut canonical pilot from `3.1.0-alpha` to `3.1`** once items 1–7 are complete and reviewed.
