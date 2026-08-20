output "workload_identity_provider" {
  description = "Full resource name of the WIF provider. Paste directly into google-github-actions/auth's `workload_identity_provider` input in both repos' workflows."
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "ci_app_service_account_email" {
  description = "Paste into google-github-actions/auth's `service_account` input in devstandards-hub's workflow."
  value       = google_service_account.ci_app.email
}

output "ci_infra_service_account_email" {
  description = "Paste into google-github-actions/auth's `service_account` input in devstandards-hub-infra's workflow."
  value       = google_service_account.ci_infra.email
}

output "state_bucket_name" {
  description = "GCS bucket name for the `backend \"gcs\" { bucket = \"...\" }` block in modules/ and platform/."
  value       = google_storage_bucket.state.name
}
