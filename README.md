# devstandards-hub-infra

Infrastructure and delivery pipeline for `devstandards-hub`: a static React SPA served
by Nginx, deployed to a single shared GKE Autopilot cluster as three Kubernetes
namespaces (`int`, `pre`, `prod`). This repo owns the platform (Terraform) and the
deploy/rollback pipeline (Helm + GitHub Actions); the app's own source and CI live in
the separate `devstandards-hub` repo.

## Repo map

```
bootstrap/    One-time, by-hand `terraform apply`. Creates the GCS state bucket, the
              WIF pool/provider, and the two federated service accounts (ci-app-sa,
              ci-infra-sa) everything else depends on. See bootstrap/README.md.

modules/      Reusable Terraform modules platform/ composes: network (VPC, subnet,
              static IP), artifact-registry (the Docker repo), gke (the Autopilot
              cluster), observability (alerting/dashboard).

platform/     The root module for the shared platform itself — one VPC, one GKE
              Autopilot cluster, one Artifact Registry repo, monitoring. Applied by
              terraform-apply.yml on every push to main. See platform/README.md,
              especially "why one cluster, three namespaces, not three clusters".

helm/
  devstandards-hub/   The one Helm chart, deployed as three independent releases
                       (one per namespace) by .github/workflows/deploy.yml. See
                       "The Helm chart" below.

.github/workflows/
  terraform-plan.yml    PR → plan, posted as a sticky PR comment. No approval gate.
  terraform-apply.yml   push to main → apply, behind the `platform` Environment gate.
  verify-gcp-access.yml Manual WIF auth smoke test.
  deploy.yml             See "Deploying" below.
  rollback.yml            See "Rolling back" below.
```

## The Helm chart

`helm/devstandards-hub/` is one chart, parameterised per environment by
`values-{int,pre,prod}.yaml` on top of `values.yaml`'s shared defaults:

| | int | pre | prod |
|---|---|---|---|
| namespace | `int` | `pre` | `prod` |
| replicas | 1 | 1 | 2 |
| HPA (min 1 / max 3 / 70% CPU) | off | on | on |
| Ingress (static IP, HTTP only) | off — `kubectl port-forward` | off — `kubectl port-forward` | on |
| PDB | `minAvailable: 1` | `minAvailable: 1` | `minAvailable: 1` |
| NetworkPolicy | GCE health-check ranges in, DNS-only out | same | same |

Every environment shares the same Deployment shape: image pinned by **digest**
(`repository@sha256:...`, never a tag — see below), requests/limits ~100m CPU / 128Mi,
readiness+liveness probes on `/` over HTTP, a non-root/read-only-filesystem
`securityContext`, and `RollingUpdate` with `maxUnavailable: 0` / `maxSurge: 1`. Every
non-obvious choice in the templates has a `WHY` comment next to it — start there for
the reasoning, this README only summarises.

**Namespaces are created by `deploy.yml`** (`helm upgrade --install --create-namespace`),
not by Terraform. This mirrors why `platform/` never configures a `kubernetes` or
`helm` Terraform provider (see `platform/README.md`): doing it in the deploy workflow
avoids ever pointing a Kubernetes/Helm provider at a cluster created in the same
Terraform run.

Validate the chart locally:

```sh
cd helm/devstandards-hub
helm lint . -f values-int.yaml   # and values-pre.yaml, values-prod.yaml
helm template devstandards-hub . -f values-prod.yaml --namespace prod
```

## The digest-promotion model

The app repo's CI builds one image per commit, pushes it once to Artifact Registry
(`europe-west2-docker.pkg.dev/devops-bpp/devstandards-hub/app`), and dispatches its digest
to this repo. Every environment then runs that **exact same digest** — "build once,
deploy many" — never a per-environment rebuild, and never a mutable tag that could
point at different bytes by the time it's pulled:

```
app repo: commit → build → push (one image, one digest)
                                 │
                    repository_dispatch("app-image-published",
                                 { image_digest, version, commit_sha })
                                 ▼
              deploy.yml → helm upgrade --install --set image.digest=<digest>
                                 │
                    always: int (no gate, no promotion guard)
                    by hand: pre, then prod — each behind its own Environment gate
                             AND the promotion guard (see below)
```

`version` (a semver string) and `commit_sha` ride alongside the digest as
human-readable/traceable metadata — `app.kubernetes.io/version` becomes a pod label,
`commit_sha` becomes the `devstandards.io/commit-sha` Deployment annotation (see "Commit
provenance" below) — neither affects what actually gets pulled; only `image.digest`
does.

## The promotion guard

Before deploying to `pre` or `prod` (never `int`), `deploy.yml` runs
`gcloud artifacts docker tags list` against the digest being deployed and **fails the
job** unless at least one attached tag matches `^[0-9]+\.[0-9]+\.[0-9]+$`. The point is
that `int` deliberately receives every published image — including ephemeral,
unreleased build artefacts — untagged and ungated; a mistyped or copy-pasted digest
must not be able to place one of those in a production-eligible environment. Only a
digest that's been through a real release (and tagged accordingly in Artifact Registry)
can be promoted further.

`rollback.yml` runs the identical check against the rollback target, but never fails on
it — a missing tag only produces a `::warning::` and a note in the job summary, and the
rollback proceeds regardless. Deploy is a planned action where blocking is cheap and
correct; rollback is a recovery action, and refusing to restore whatever was already
serving traffic — because it predates this tagging convention, or lost its tag to an
Artifact Registry cleanup policy — would let a process control cause an outage.
Controls on the way in are strict; controls on the way back are permissive.

## Commit provenance

`deploy.yml` stamps every Deployment with `devstandards.io/commit-sha` and
`devstandards.io/image-digest` annotations (alongside the existing
`app.kubernetes.io/version` label), so `kubectl describe deployment` is
self-documenting — no cross-referencing a CI run needed to see what's running and which
commit produced it. `commit_sha` is optional on both triggers (a manual
`workflow_dispatch` deploy may not have one to hand) and defaults to `"unknown"` rather
than failing.

`rollback.yml` resolves commit SHAs for its suspect-commit issue (see "Rolling back")
in two tiers: **primarily** the `org.opencontainers.image.revision` OCI annotation on
the image manifest itself (baked in at build time, so it survives the Helm release
being deleted or the namespace recreated), **falling back** to the
`devstandards.io/commit-sha` Deployment annotation above if that's missing. The app
repo's build pipeline does not set the OCI annotation yet — until it does, tier one
always misses and tier two is what actually resolves anything.

## Deploying

Automatically, to `int`: the app repo's publish pipeline fires a `repository_dispatch`
(`type: app-image-published`, payload `{ image_digest, version, commit_sha }`) at
`devstandards-hub-infra`; `deploy.yml` picks it up and deploys straight to `int` — no
approval gate, no promotion guard.

By hand, to any environment (used for promoting a digest that's already passed `int`
to `pre`, and `pre` to `prod`):

```sh
gh workflow run deploy.yml \
  --repo mawusix/devstandards-hub-infra \
  -f environment=prod \
  -f image_digest=sha256:<64 hex chars> \
  -f version=1.4.2 \
  -f commit_sha=<git sha, optional>
```

`deploy.yml` validates `image_digest` against `^sha256:[a-f0-9]{64}$` before doing
anything else, authenticates as `ci-infra-sa` via WIF, and — for `pre`/`prod` only —
runs the promotion guard (see "The promotion guard" above) before it ever touches the
cluster. It then runs
`helm upgrade --install --wait --atomic --timeout 5m --history-max 10`. If the rollout
doesn't reach Ready in time, `--atomic` rolls the release back automatically — a
subsequent step dumps `helm history` + pod state behind an explicit `::error::` so that
auto-rollback shows up in the log instead of looking like a quiet success.

## Rolling back

```sh
gh workflow run rollback.yml --repo mawusix/devstandards-hub-infra -f environment=prod
```

Goes through the **same Environment gate as `deploy.yml`** — rolling prod back is not
lower-stakes than deploying to it. `rollback.yml` then:

1. Records the currently-deployed (bad) image digest and its
   `devstandards.io/commit-sha` annotation (the fallback provenance source).
2. Runs `helm rollback` (defaults to the immediately preceding revision) and
   `helm history` for the audit trail.
3. Records the now-restored (good) image digest, its `devstandards.io/commit-sha`
   annotation, and its `app.kubernetes.io/version` label.
4. Runs the promotion guard against the restored digest — **warns, does not fail** (see
   "The promotion guard" above).
5. Best-effort resolves both digests to app-repo commit SHAs (see "Commit provenance"
   above: OCI annotation first, Deployment annotation fallback second) and opens a
   **GitHub issue** (not a PR) in `devstandards-hub` — always, whether or not
   provenance resolved — listing the commits between them as suspects when it did.
6. Reports the restored version/digest and the promotion-guard result in
   `$GITHUB_STEP_SUMMARY`, regardless of how either check came out.

Rollback, not roll-forward, is the safe default here specifically because the app is a
stateless SPA with no database, no migrations, and no API contract — reverting the
image fully reverts everything that could have changed. That reasoning would NOT hold
for a service with a database: rolling the app back while a migration stays applied can
make things worse, not better.

The pipeline deliberately does **not** try to auto-revert a specific commit: several
commits may have merged to `main` since the last known-good release, and a failed
rollout alone doesn't tell you which one (if any) is actually at fault. Automating
*detection and notification* is safe; automating *remediation* would mean guessing at a
root cause the pipeline has no way to establish — so it raises visibility (an issue,
left open, listing suspects) and leaves diagnosis and any revert to a human.

## Environments and gates

| Environment | Trigger | Approval gate | Reached at |
|---|---|---|---|
| `int` | `repository_dispatch` (every published image) or manual | none | `kubectl port-forward -n int svc/devstandards-hub 8080:80` |
| `pre` | manual (`workflow_dispatch`) | GitHub Environment `pre` (required reviewers, configured in Settings → Environments) | `kubectl port-forward -n pre svc/devstandards-hub 8080:80` |
| `prod` | manual (`workflow_dispatch`) | GitHub Environment `prod` (required reviewers) | `http://<reserved static IP>/` (HTTP only — see `templates/ingress.yaml` for why no TLS) |

`rollback.yml` re-enters whichever of these gates matches the environment being rolled
back — it does not bypass them.

## Manual setup this repo depends on but does not create
- **Not built yet, tracked for later:** the app repo's build pipeline should set the
  standard OCI annotations (`org.opencontainers.image.revision`, `.version`, `.source`)
  on each pushed image manifest. Until it does, `rollback.yml`'s provenance lookup
  always falls through to its second tier (the `devstandards.io/commit-sha` Deployment
  annotation `deploy.yml` already stamps — see "Commit provenance" above) rather than
  the OCI annotation itself — this is exactly what that fallback is for, and nothing
  here breaks in the meantime. If a digest resolves via neither tier (e.g. a manual
  deploy that also omitted `commit_sha`), the rollback still completes and the
  resulting issue says provenance was unavailable rather than guessing.
