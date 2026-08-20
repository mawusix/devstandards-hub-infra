# WHY cleanup policies matter here specifically: CI tags every image with its Git SHA
# (see devstandards-hub's build workflow), never reusing a tag. That means the image
# stream never naturally shrinks the way a "latest"-only or version-bumped repo would —
# every single commit that touches the app adds one more permanent, distinct image
# unless something actively prunes it. Left alone, storage cost grows without bound for
# the lifetime of the project. The two policies below bound that growth two ways:
# keeping a safety margin of recent SHAs for rollback, and reclaiming untagged layers
# left behind when a tag is moved/deleted (e.g. a failed/superseded build push) after a
# short grace period.
resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "SHA-tagged container images for devstandards-hub."

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.keep_recent_count
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.delete_untagged_older_than_days * 24}h"
    }
  }
}