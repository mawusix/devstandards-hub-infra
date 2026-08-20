output "repository_id" {
  description = "Name of the Artifact Registry repository."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_url" {
  description = "Full pushable/pullable repository path: <region>-docker.pkg.dev/<project>/<repository_id>. CI appends /<image>:<tag> to this."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}