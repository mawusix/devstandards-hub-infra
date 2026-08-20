# WHY these eleven and not "just enable what's needed right now": everything modules/ and
# platform/ will create later (VPC, GKE Autopilot, Artifact Registry, Helm-deployed
# workloads, WIF-authenticated CI) depends transitively on one of these APIs already
# being on. Enabling the full set once here means a fresh clone of modules/ never fails
# its first `terraform apply` on a "service not enabled" error.
locals {
  bootstrap_apis = [
    "container.googleapis.com",            # GKE Autopilot cluster (modules/, later)
    "artifactregistry.googleapis.com",     # container image repo (modules/, later)
    "compute.googleapis.com",              # VPC/subnets/firewall (modules/, later)
    "iam.googleapis.com",                  # service accounts + IAM bindings (this directory)
    "iamcredentials.googleapis.com",       # WIF token exchange / SA impersonation
    "sts.googleapis.com",                  # WIF OIDC token exchange
    "cloudresourcemanager.googleapis.com", # project-level IAM bindings
    "monitoring.googleapis.com",           # Cloud Monitoring (platform/, later)
    "logging.googleapis.com",              # Cloud Logging (platform/, later)
    "secretmanager.googleapis.com",        # app secrets (platform/, later)
    "billingbudgets.googleapis.com",       # the budget resource below
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.bootstrap_apis)

  project = var.project_id
  service = each.value

  # WHY false: disabling APIs on `terraform destroy` is almost never wanted for a
  # bootstrap layer. If someone ever tears down just this directory, disabling
  # container/artifactregistry/iam out from under a still-live GKE cluster and its
  # WIF-authenticated CI pipelines would break far more than it cleans up.
  disable_on_destroy = false
}
