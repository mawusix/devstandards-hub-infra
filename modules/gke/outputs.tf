output "cluster_name" {
  description = "Name of the GKE Autopilot cluster. Pass to `gcloud container clusters get-credentials` in the deploy workflow."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "Region the cluster runs in. Pass alongside cluster_name to `gcloud container clusters get-credentials --region`."
  value       = google_container_cluster.this.location
}

output "cluster_id" {
  description = "Fully-qualified cluster resource ID."
  value       = google_container_cluster.this.id
}

output "endpoint" {
  description = "Public IP of the cluster's control plane endpoint."
  value       = google_container_cluster.this.endpoint
}
