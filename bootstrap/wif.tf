# WHY one pool, one provider for both CI service accounts: GitHub Actions is the only
# external identity provider this project federates with, for both repos. Splitting
# into two pools would add operational surface (two provider URLs to manage in two
# repos' workflow files) for no security benefit — the actual per-repo boundary is
# enforced per-service-account below, via the principalSet each SA is bound to.
resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens for CI. No service account keys are issued anywhere in this project."

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-oidc"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    # WHY google.subject is mapped even though the brief only asked for
    # repository/ref/actor: it's a mandatory mapping for any OIDC provider (Terraform
    # rejects the resource without it), and it's what shows up as the caller identity
    # in Cloud Audit Logs, so mapping it to the full GitHub OIDC subject claim keeps
    # audit entries traceable back to the exact workflow run.
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # WHY this condition is load-bearing, not decorative: without it, attribute.repository
  # is attacker-controlled input straight from the OIDC token — any GitHub repo on
  # earth, not just this org's, could otherwise present a token whose `repository`
  # claim matches one of the principalSet bindings below. Restricting to the owner here
  # is the actual security boundary; the per-SA principalSet bindings in iam.tf then
  # narrow it further to exactly one repo each.
  attribute_condition = "assertion.repository_owner == \"${var.github_owner}\""

  depends_on = [google_project_service.this]
}
