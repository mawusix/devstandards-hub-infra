# WHY a data source instead of a project_number variable: the brief's "no hardcoded
# project IDs... all via variables" is about the values a human has to choose (project,
# owner, billing account). The project number is a mechanical fact derivable from
# project_id, not a choice — fetching it avoids a fourth variable that could drift out
# of sync with project_id if someone typo'd it.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  ci_app_repo   = "${var.github_owner}/devstandards-hub"
  ci_infra_repo = "${var.github_owner}/devstandards-hub-infra"

  wif_pool_resource = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}"
}

# ---------------------------------------------------------------------------
# ci-app-sa — federated from devstandards-hub CI. Only ever needs to push
# container images, so it gets exactly one role.
# ---------------------------------------------------------------------------

resource "google_service_account" "ci_app" {
  project      = var.project_id
  account_id   = "ci-app-sa"
  display_name = "CI - devstandards-hub app pipeline"
  description  = "Federated via Workload Identity from ${local.ci_app_repo}. No key ever issued."

  depends_on = [google_project_service.this]
}

resource "google_service_account_iam_member" "ci_app_wif" {
  service_account_id = google_service_account.ci_app.name
  role                = "roles/iam.workloadIdentityUser"

  # WHY principalSet on attribute.repository, not a principal:// on one subject: the
  # GitHub OIDC subject claim is scoped to the triggering ref, not just the repo —
  # "repo:<owner>/<repo>:ref:refs/heads/main" for a branch push, but
  # "repo:<owner>/<repo>:pull_request" for a PR event, and a different form again when
  # a workflow targets a GitHub environment. Binding a single principal:// subject
  # would therefore authorise one trigger type on one ref and silently 403 everything
  # else — the PR-triggered `terraform plan` workflow would fail even though the
  # merge-triggered `apply` worked. Binding the principalSet on attribute.repository
  # instead scopes to the repository itself, which is the boundary the brief asks for,
  # and the provider's attribute_condition in wif.tf already prevents any repo outside
  # this owner from presenting a matching claim.
  member = "principalSet://iam.googleapis.com/${local.wif_pool_resource}/attribute.repository/${local.ci_app_repo}"

  depends_on = [google_iam_workload_identity_pool_provider.github_actions]
}

resource "google_project_iam_member" "ci_app_artifactregistry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.ci_app.email}"
}

# ---------------------------------------------------------------------------
# ci-infra-sa — federated from devstandards-hub-infra CI. Needs enough to
# provision the platform (VPC, GKE, Artifact Registry, monitoring) without
# roles/editor or roles/owner.
# ---------------------------------------------------------------------------

resource "google_service_account" "ci_infra" {
  project      = var.project_id
  account_id   = "ci-infra-sa"
  display_name = "CI - devstandards-hub-infra pipeline"
  description  = "Federated via Workload Identity from ${local.ci_infra_repo}. No key ever issued."

  depends_on = [google_project_service.this]
}

resource "google_service_account_iam_member" "ci_infra_wif" {
  service_account_id = google_service_account.ci_infra.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${local.wif_pool_resource}/attribute.repository/${local.ci_infra_repo}"

  depends_on = [google_iam_workload_identity_pool_provider.github_actions]
}

locals {
  # WHY these five and not roles/editor: this is the minimum predefined-role set that
  # together covers creating/updating the VPC (compute.networkAdmin), the GKE Autopilot
  # cluster (container.admin), the Artifact Registry repo (artifactregistry.admin), and
  # platform monitoring (monitoring.editor) that modules/ and platform/ will add later —
  # plus iam.serviceAccountUser, which Terraform needs to attach service accounts to
  # resources it creates (e.g. GKE node identity) without granting broad IAM-admin
  # rights.
  ci_infra_project_roles = [
    "roles/container.admin",
    "roles/compute.networkAdmin",
    "roles/artifactregistry.admin",
    "roles/monitoring.editor",
    "roles/iam.serviceAccountUser",
  ]
}

resource "google_project_iam_member" "ci_infra_roles" {
  for_each = toset(local.ci_infra_project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci_infra.email}"
}

# WHY a bucket IAM member here instead of adding roles/storage.objectAdmin to
# ci_infra_project_roles above: ci-infra-sa only ever needs to read/write Terraform
# state objects in this one bucket. A project-level grant would hand it object-admin
# rights over every other bucket created later too (app assets, log exports, etc.) —
# more blast radius than the CD pipeline needs for a role that's really "can manage
# this specific bucket's contents".
resource "google_storage_bucket_iam_member" "ci_infra_state_bucket_object_admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci_infra.email}"
}
