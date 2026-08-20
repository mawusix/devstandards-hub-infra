# bootstrap/

Solves the chicken-and-egg problem for this project: everything else (`modules/`,
`platform/`, and CI in both `devstandards-hub` and `devstandards-hub-infra`) needs a
GCS bucket to store remote state in and a Workload Identity Federation setup to
authenticate as, but those things have to be created by *something* first. That
something is this directory.

It creates, and only creates:

1. The eleven GCP APIs everything downstream needs enabled.
2. The GCS bucket used as remote state backend by every other repo/module.
3. A Workload Identity Federation pool + GitHub OIDC provider (no service account keys,
   anywhere).
4. Two service accounts (`ci-app-sa`, `ci-infra-sa`), each bound to exactly one GitHub
   repo via WIF, each with the minimum predefined roles for its job.
5. A billing budget with alerts at 50/90/100% of spend (optional, see below).

It does **not** create the VPC, GKE cluster, Artifact Registry repo, or any Helm
charts — those belong to `modules/` and `platform/`, which run in CI using the service
accounts this directory creates.

## Why local state here (and only here)

Every other piece of Terraform in this project uses a `backend "gcs"` block pointed at
the bucket this directory creates. This directory can't do the same thing to itself —
the bucket doesn't exist until after the first apply, so pointing this directory's own
backend at it would be a circular dependency (and a two-step migration dance every time
someone re-bootstraps a project from scratch).

Local state is safe specifically *here* because:

- It's applied exactly once per project, by a human, not by CI.
- Nothing else needs to read this state remotely — the values other repos need
  (bucket name, WIF provider name, SA emails) are consumed as plain strings/secrets,
  not via `terraform_remote_state`.
- The state file itself only describes bootstrap's own handful of resources, so the
  "don't lose it" risk is small and it's easy to keep a private backup of
  `terraform.tfstate` if you want one.

Every resource this directory creates is a real, importable GCP resource
(`google_project_service`, `google_storage_bucket`, `google_iam_workload_identity_pool`,
etc.) — if the local state file is ever lost, everything here can be re-imported by ID
rather than being unrecoverable.

## Prerequisites

- `terraform` >= 1.9
- `gcloud` CLI, authenticated as a principal with:
  - `roles/owner` or an equivalent bundle (`resourcemanager.projects.setIamPolicy`,
    `serviceusage.services.enable`, `iam.serviceAccounts.create`,
    `iam.workloadIdentityPools.create`, `storage.buckets.create`) on `devops-bpp`
  - a billing-account role (e.g. `roles/billing.costsManager`) on the billing account,
    only if you're leaving `create_budget = true`

## Exact commands to run first

```sh
# Authenticate the gcloud CLI itself (used for any manual gcloud calls / troubleshooting)
gcloud auth login

# Authenticate Application Default Credentials — this is what the Terraform google
# provider actually uses
gcloud auth application-default login

# Point gcloud at the right project so ad-hoc commands don't need --project every time
gcloud config set project devops-bpp

# Sanity check: confirms serviceusage.googleapis.com is already enabled (it is by
# default on any GCP project), which google_project_service resources need in order
# to enable everything else
gcloud services list --enabled --project devops-bpp | grep serviceusage
```

## Apply order

There's only one `terraform apply` — every ordering constraint below is expressed via
`depends_on` or resource references inside the config, so Terraform's graph handles it.
Conceptually, what happens in what order:

1. `apis.tf` — enable all eleven APIs (`google_project_service`, one per API).
2. `state.tf` — create the GCS state bucket (depends on APIs, specifically
   `storage.googleapis.com` being implicitly available and `cloudresourcemanager` for
   project-scoped calls).
3. `wif.tf` — create the WIF pool, then the OIDC provider inside it (depends on
   `iam.googleapis.com` / `sts.googleapis.com`).
4. `iam.tf` — create `ci-app-sa` and `ci-infra-sa`, bind each to its repo's
   `principalSet` via WIF, then grant each SA its project/bucket IAM roles.
5. `budget.tf` — create the billing budget last (only if `create_budget = true`).

```sh
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if you need to override any defaults

terraform init
terraform plan
terraform apply
```

## If the budget resource fails

Billing budget creation needs a billing-account-level IAM role, not just a
project-level one — free-trial accounts don't always grant that to the account owner's
default credentials. If `terraform apply` fails specifically on
`google_billing_budget.monthly`, set `create_budget = false` in `terraform.tfvars`, run
`terraform apply` again, and create the budget by hand in
**Billing → Budgets & alerts** in the console instead (target: ~£50, alerts at 50/90/100%).

## Outputs

After `terraform apply`, get everything CI needs in one go:

```sh
terraform output -raw workload_identity_provider
terraform output -raw ci_app_service_account_email
terraform output -raw ci_infra_service_account_email
terraform output -raw state_bucket_name
```

## Minimal GitHub Actions smoke test

Add this as a one-off workflow (or the first steps of a real one) in whichever repo
you're testing — swap `service_account` for the app or infra SA email as appropriate.

```yaml
name: gcp-auth-smoke-test

on: workflow_dispatch

permissions:
  contents: read
  id-token: write   # required — this is what lets GitHub mint the OIDC token WIF exchanges

jobs:
  smoke-test:
    runs-on: ubuntu-latest
    steps:
      - id: auth
        uses: google-github-actions/auth@v2
        with:
          project_id: devops-bpp
          workload_identity_provider: ${{ secrets.WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.CI_SERVICE_ACCOUNT_EMAIL }}

      - uses: google-github-actions/setup-gcloud@v2

      - run: gcloud auth list
```

Store `terraform output -raw workload_identity_provider` and the relevant service
account email as repo (or org) secrets named `WORKLOAD_IDENTITY_PROVIDER` and
`CI_SERVICE_ACCOUNT_EMAIL` — don't hardcode them in the workflow file, since the
provider name embeds the project number.
