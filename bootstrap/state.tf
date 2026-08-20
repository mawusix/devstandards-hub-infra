locals {
  # WHY derive rather than require: GCP project IDs are already globally unique, so a
  # bucket name built from project_id is very likely available without the extra
  # complexity of a random suffix — and it stays predictable for the `backend "gcs"`
  # blocks that modules/ and platform/ will hardcode.
  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_id}-tfstate")
}

# WHY this is the ONLY bucket bootstrap creates: every other repo's Terraform
# (modules/, platform/) points its own `backend "gcs"` block at this bucket with a
# distinct `prefix`. Bootstrap itself does NOT use this bucket as its own backend —
# see versions.tf and the README for why local state is correct here.
resource "google_storage_bucket" "state" {
  name     = local.state_bucket_name
  project  = var.project_id
  location = var.region

  # WHY uniform (not fine-grained ACLs): the only access this bucket ever needs is
  # project/bucket-level IAM bindings (see iam.tf's ci-infra-sa binding). Uniform access
  # keeps that the single source of truth instead of ACLs and IAM silently disagreeing.
  uniform_bucket_level_access = true

  # WHY enforced: state files can contain secrets in plaintext (DB passwords, API keys
  # pulled into resource attributes/outputs). Enforcing public access prevention makes
  # it impossible for a future misconfigured IAM binding to expose the bucket to
  # allUsers/allAuthenticatedUsers, even by accident.
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      # WHY bound rather than unbounded: versioning alone keeps every historical state
      # version forever. Since state changes on every apply, that's unbounded storage
      # growth for a file that's a few KB at most — bounding it keeps enough history to
      # recover from a bad apply without the bucket growing forever.
      num_newer_versions = var.state_bucket_noncurrent_version_count
    }
  }

  # WHY false: this bucket is the single source of truth for remote state across every
  # repo. A careless `terraform destroy` scoped to just this directory must not be able
  # to silently wipe out all state history for everything else.
  force_destroy = false

  depends_on = [google_project_service.this]
}
