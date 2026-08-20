# platform/

The root module for the shared platform: one VPC, one GKE Autopilot cluster, one
Artifact Registry repository, and the monitoring around them. Applied by
`terraform-apply.yml` on every push to `main`, behind the `platform` GitHub Environment
approval gate. See `../bootstrap/README.md` for the layer underneath this one (state
bucket, WIF, service accounts) — that has to exist first and is applied by hand, once.

It calls four modules, in `../modules/`:

- `network` — custom-mode VPC, one subnet (`europe-west2`) with secondary ranges for
  pods/services, Private Google Access on, no Cloud NAT, one global static IP.
- `artifact-registry` — the Docker repo CI pushes SHA-tagged images to, with cleanup
  policies.
- `gke` — the single Autopilot cluster.
- `observability` — email alerting, an uptime check, and a dashboard.

## Why one cluster, three namespaces — not three clusters

int, pre, and prod are **Kubernetes namespaces inside one GKE Autopilot cluster**, not
three separate clusters. This repo's Terraform provisions exactly one of everything
(one VPC, one cluster, one Artifact Registry repo); the three environments are created
later, as namespaces, by Helm.

Reasoning:

- **Cost.** Three Autopilot clusters means three regional control planes and three
  separate baseline Autopilot footprints, on a GCP free-trial account with a fixed
  credit budget (£227) that also has to cover the VPC, Artifact Registry storage, and
  monitoring. A single cluster with three namespaces has one control plane and shares
  the Autopilot baseline across all three environments' workloads.
- **What actually needs isolating.** int/pre/prod need separation of *workloads and
  config* (different image tags, different replica counts, different env vars per
  `helm/devstandards-hub/values-{int,pre,prod}.yaml`) — not separation of the compute
  platform itself. Kubernetes namespaces plus RBAC (and, if ever needed, per-namespace
  NetworkPolicy) give that level of isolation. This is a portfolio/demo project for a
  stateless SPA with no compliance requirement (e.g. PCI, data residency) forcing
  *physical* separation between environments — if that requirement existed, three
  clusters (or three projects) would be the right call instead.
- **Terraform's job stops at the platform.** This root module has no concept of
  "environment" at all — it creates the shared platform once. Namespaces,
  environment-specific Helm releases, and their config are entirely the deploy
  workflow's concern, applied with `helm upgrade --install --namespace {int,pre,prod}`
  against the one cluster `terraform output cluster_name`/`cluster_location` point at.

## Why platform/ never configures a kubernetes or helm provider

Terraform's `kubernetes` and `helm` providers need a live cluster endpoint and
credentials at provider-configuration time — which happens before Terraform's resource
graph runs, not after. On the very first `apply`, the GKE cluster this module creates
doesn't exist yet when the kubernetes/helm provider would try to configure itself
against it: a classic chicken-and-egg failure that either errors outright or produces
inconsistent plans depending on provider version and Terraform version. Splitting
"create the cluster" (this repo, this apply) from "create namespaces/releases in it"
(the deploy workflow, using `gcloud container clusters get-credentials` + `helm`, no
Terraform Kubernetes provider involved at all) avoids the problem entirely by never
putting both concerns in the same Terraform run.

## Why no Cloud NAT

See the WHY comment in `../modules/network/main.tf` for the full reasoning — short
version: the app is a static SPA served by Nginx with no backend and no outbound calls
of its own. The only egress traffic a pod ever generates is the image pull from
Artifact Registry, which Private Google Access already covers for private nodes. Adding
Cloud NAT purely to cover a code path that doesn't exist would cost ~$32/month for
nothing. If the app ever grows a real outbound dependency, this stops being true and
NAT (or an egress proxy) becomes necessary.

## Why the GKE control plane endpoint is public with no authorized networks

See the WHY comment in `../modules/gke/main.tf`. Short version: GitHub-hosted Actions
runners don't have a stable IP range to put in `master_authorized_networks`, and
standing up a self-hosted runner or bastion just to get one is infrastructure this
project doesn't otherwise need. Access is controlled by identity (Workload Identity
Federation + RBAC) instead of network ACLs — an accepted tradeoff for a demo project,
not the choice a production system handling sensitive data should make.

## Apply order

There's one `terraform apply` in this directory; Terraform's dependency graph (module
input/output references in `main.tf`) handles ordering within it. Conceptually:

1. `network` — VPC, subnet with secondary ranges, static IP. Nothing else can start
   until this exists, since gke and observability both consume its outputs.
2. `artifact_registry` — independent of network/gke, can provision in parallel with
   them.
3. `gke` — depends on `network`'s `network_id`/`subnetwork_id`/range names.
4. `observability` — depends on `network`'s `ingress_ip_address` (for the uptime check)
   and `gke`'s `cluster_name` (to scope the restart-count dashboard widget).

```sh
# One-time prerequisite, done once in bootstrap/ by a human — see bootstrap/README.md.
# Everything below runs in CI (terraform-plan.yml / terraform-apply.yml), not by hand.

cd platform
terraform init
terraform plan    # runs in terraform-plan.yml on every PR, output posted as a PR comment
terraform apply   # runs in terraform-apply.yml on push to main, behind the `platform`
                   # GitHub Environment's required reviewers
```

## Local dev setup

This repo ships a `pre-push` hook (`../.githooks/pre-push`) that runs
`terraform fmt -check -recursive` before every push — the same check
`terraform-plan.yml` runs first, so a formatting issue fails fast locally
instead of silently blocking the CI plan job (fmt check runs before the plan
step, with no `continue-on-error`). `core.hooksPath` isn't tracked by git, so
each clone needs to opt in once:

```sh
git config core.hooksPath .githooks
```

## Outputs

```sh
terraform output -raw cluster_name
terraform output -raw cluster_location
terraform output -raw artifact_registry_url
terraform output -raw ingress_ip
```

`cluster_name` + `cluster_location` are exactly what the deploy workflow needs for
`gcloud container clusters get-credentials <cluster_name> --region <cluster_location>`
before running Helm. `ingress_ip` is what the Ingress's
`kubernetes.io/ingress.global-static-ip-name` annotation targets (via the reserved
address's *name*, not its IP — see `../modules/network/outputs.tf`'s `ingress_ip_name`).

## Cost reasoning, summarised

| Decision | Saves | At the cost of |
|---|---|---|
| One Autopilot cluster (namespaces, not clusters) for int/pre/prod | 2× control plane + baseline footprint | Physical isolation between environments (RBAC/namespace isolation instead) |
| No Cloud NAT | ~$32/month | Any future outbound call from a pod would need this revisited |
| `deletion_protection = false` on the cluster | A full teardown after the demo doesn't need a manual unprotect step | Nothing destroys this cluster by accident *for you* — CI apply/destroy still needs deliberate action |
| Artifact Registry cleanup policies (keep 10, delete untagged >7d) | Unbounded storage growth from a SHA-per-commit tagging scheme | Rollback is only possible to the 10 most recent images, not full history |